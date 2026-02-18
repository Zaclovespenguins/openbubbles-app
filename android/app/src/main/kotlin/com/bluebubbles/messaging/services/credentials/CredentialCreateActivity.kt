package com.bluebubbles.messaging.services.credentials

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.credentials.CreatePasswordRequest
import androidx.credentials.CreatePasswordResponse
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.provider.PendingIntentHandler
import androidx.fragment.app.FragmentActivity
import com.bluebubbles.messaging.services.rustpush.APNClient
import com.bluebubbles.messaging.services.rustpush.APNService
import com.upokecenter.cbor.CBORObject
import org.json.JSONArray
import uniffi.rust_lib_bluebubbles.InsertKeychainCallback
import uniffi.rust_lib_bluebubbles.NativePushState
import uniffi.rust_lib_bluebubbles.RetrieveKeysCallback
import uniffi.rust_lib_bluebubbles.SavedPasskey
import java.io.ByteArrayOutputStream
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.UUID
import org.json.JSONObject
import uniffi.rust_lib_bluebubbles.SavedPassword

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class CredentialCreateActivity : FragmentActivity() {

    val client = APNClient(this)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val request = PendingIntentHandler.retrieveProviderCreateCredentialRequest(intent)
        if (request == null) {
            finishAndRemoveTask()
            return
        }

        val continueFlow = {
            CredentialWebAuthnUtils.ensurePrivilegedAllowlistFresh(this) { error ->
                if (error != null) {
                    Log.e("Webauthn", "Unable to refresh privileged app allowlist", error)
                    finishAndRemoveTask()
                    return@ensurePrivilegedAllowlistFresh
                }

                client.bind { service: APNService ->
                    service.pushState?.let {
                        handleService(it)
                    } ?: finishAndRemoveTask()
                }
            }
        }

        if (request.callingRequest is CreatePublicKeyCredentialRequest) {
            CredentialUserAuth.authenticateForPasskey(
                this,
                onSuccess = continueFlow,
                onFailure = { error ->
                    Log.i("CredentialCreate", "User authentication failed or canceled: $error")
                    finish()
                }
            )
        } else {
            continueFlow()
        }
    }

    fun handleService(service: NativePushState) {
        val request = PendingIntentHandler.retrieveProviderCreateCredentialRequest(intent)
        if (request == null) {
            finishAndRemoveTask()
            return
        }

        if (request.callingRequest is CreatePublicKeyCredentialRequest) {
            val credentialRequest = request.callingRequest as CreatePublicKeyCredentialRequest

            val requestJson = JSONObject(credentialRequest.requestJson)
            val rpJson = requestJson.optJSONObject("rp") ?: JSONObject()
            val rpId = rpJson.optString("id", "")
            val challenge = requestJson.getString("challenge")

            val origin = CredentialService.appInfoToOrigin(this, request.callingAppInfo)
            val userJson = requestJson.getJSONObject("user")

            val credentialId = ByteArray(20)
            SecureRandom().nextBytes(credentialId)

            val spec = ECGenParameterSpec("secp256r1")
            val keyPairGen = KeyPairGenerator.getInstance("EC")
            keyPairGen.initialize(spec)
            val keyPair = keyPairGen.genKeyPair()

            val tag = encodeUserTag(userJson)
            val userId = if (userJson.has("id")) base64UrlDecode(userJson.getString("id")) else null

            val clientDataJson = JSONObject()
                .put("type", "webauthn.create")
                .put("challenge", challenge)
                .put("origin", origin)
                .toString().replace("\\/", "/")
                .toByteArray(Charsets.UTF_8)

            val clientDataHash = credentialRequest.clientDataHash ?: MessageDigest.getInstance("SHA-256").digest(clientDataJson)

            val rpIdHash = MessageDigest.getInstance("SHA-256").digest(rpId.toByteArray(Charsets.UTF_8))
            val flags = (0x01 or 0x04 or 0x08 or 0x10 or 0x40).toByte() // UP + AT
            val signCount = byteArrayOf(0, 0, 0, 0)
            val aaguid = ByteArray(16) { 0 }

            val publicKey = keyPair.public as ECPublicKey
            val coseKey = encodeCosePublicKey(publicKey)

            val authData = ByteArrayOutputStream().apply {
                write(rpIdHash)
                write(byteArrayOf(flags))
                write(signCount)
                write(aaguid)
                writeU16(credentialId.size)
                write(credentialId)
                write(coseKey)
            }.toByteArray()

            val signature = Signature.getInstance("SHA256withECDSA").apply {
                initSign(keyPair.private)
                update(authData)
                update(clientDataHash)
            }.sign()


            val attestationObject = CBORObject.NewMap().apply {
                Add("fmt", "packed")
                Add("authData", authData)
                Add(
                    "attStmt",
                    CBORObject.NewMap().apply {
                        Add("alg", -7)
                        Add("sig", signature)
                    }
                )
            }.EncodeToBytes()

            val publicKeyDer = keyPair.public.encoded
            val responseJson = JSONObject()
                .put("id", base64UrlEncode(credentialId))
                .put("rawId", base64UrlEncode(credentialId))
                .put("type", "public-key")
                .put("authenticatorAttachment", "platform")
                .put("clientExtensionResults", JSONObject())
                .put(
                    "response",
                    JSONObject()
                        .put("clientDataJSON", base64UrlEncode(clientDataJson))
                        .put("attestationObject", base64UrlEncode(attestationObject))
                        .put("authenticatorData", base64UrlEncode(authData))
                        .put("publicKeyAlgorithm", -7)
                        .put("publicKey", base64UrlEncode(publicKeyDer))
                        .put("transports", JSONArray().put("internal"))
                )

            val createPublicKeyCredResponse = CreatePublicKeyCredentialResponse(responseJson.toString())

            val result = Intent()
            service.getSiteConfig(rpId, object : RetrieveKeysCallback {
                override fun keys(passwords: List<SavedPassword>, passkeys: List<SavedPasskey>) {
                    val matching = findMatchingRecordId(passkeys, userId)
                    val recordId = matching ?: UUID.randomUUID().toString().uppercase()
                    service.keychainPasskeyInsert(rpId, recordId, credentialId, tag, keyPair.private.encoded, object : InsertKeychainCallback {
                        override fun done(error: String?) {
                            if (error != null) {
                                Log.e("Webauthn", "Error $error")
                                finish()
                                return
                            }

                            // Set the CreateCredentialResponse as the result of the Activity
                            PendingIntentHandler.setCreateCredentialResponse(
                                result,
                                createPublicKeyCredResponse
                            )
                            setResult(RESULT_OK, result)
                            finish()
                        }
                    })
                }
            })
        } else if (request.callingRequest is CreatePasswordRequest) {
            val request = request.callingRequest as CreatePasswordRequest
            val result = Intent()
            service.keychainPasswordInsert(
                request.origin ?: "",
                request.id,
                request.password,
                object : InsertKeychainCallback {
                    override fun done(error: String?) {
                        if (error != null) {
                            Log.e("Credential", "Error $error")
                            finish()
                            return
                        }

                        PendingIntentHandler.setCreateCredentialResponse(
                            result,
                            CreatePasswordResponse()
                        )
                        setResult(RESULT_OK, result)
                        finish()
                    }
                }
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        client.destroy()
    }
}

private fun ByteArrayOutputStream.writeU16(value: Int) {
    write(byteArrayOf(((value shr 8) and 0xFF).toByte(), (value and 0xFF).toByte()))
}

private fun findMatchingRecordId(passkeys: List<SavedPasskey>, userId: ByteArray?): String? {
    if (userId == null) return null
    for (passkey in passkeys) {
        val tagUserId = decodeUserTag(passkey.tag).id
        if (tagUserId != null && tagUserId.contentEquals(userId)) {
            return passkey.credId
        }
    }
    return null
}
