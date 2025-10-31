package com.bluebubbles.messaging.services.rustpush

import android.annotation.SuppressLint
import android.app.AppOpsManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import android.util.Log
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import com.bluebubbles.messaging.services.rustpush.eap_aka.EapAkaChallenge
import com.bluebubbles.messaging.services.rustpush.eap_aka.EapAkaResponse
import com.bluebubbles.messaging.services.rustpush.eap_aka.EapAkaResponse.getImsiEap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import uniffi.rust_lib_bluebubbles.CarrierHandler
import uniffi.rust_lib_bluebubbles.EntitlementHandler
import uniffi.rust_lib_bluebubbles.getCarrier
import java.util.Random

class SMSLessAuthGateway: MethodCallHandlerImpl() {

    companion object {
        const val tag = "sms-less-auth-gateway"

        // adb shell appops set --uid com.openbubbles.messaging USE_ICC_AUTH_WITH_DEVICE_IDENTIFIER allow
        fun hasIccAuthWithDeviceIdentifierPermission(context: Context): Boolean {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.checkOpNoThrow(
                "android:use_icc_auth_with_device_identifier",
                android.os.Process.myUid(), context.packageName)
            return mode == AppOpsManager.MODE_ALLOWED
        }
    }

    // subscriberid works with icc auth, suppress lint
    @SuppressLint("MissingPermission")
    override fun handleMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
        context: Context
    ) {
        val subscription = call.argument<Int>("subscription")!!

        var telephonyManager = (context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            telephonyManager = telephonyManager.createForSubscriptionId(subscription)
        }
        val carrierMccMnc = telephonyManager.simOperator    


        if (!hasIccAuthWithDeviceIdentifierPermission(context)) {
            result.error("No ICC auth permission!", null, null)
        }

        Log.i("MCCMNC", "$carrierMccMnc ${telephonyManager.subscriberId}")

        val realm = "nai.epc"

        val client = APNClient(context)
        client.bind { service: APNService ->
            service.pushState.getEntitlements(object : EntitlementHandler {
                override fun gotUser(gateway: String?, error: String?) {
                    if (gateway == null) {
                        result.error(error ?: "No error", null, null)
                        return
                    }

                    result.success(gateway)
                }

                override fun performChallenge(challenge: String): String? {
                    val challenge2 = EapAkaChallenge.parseEapAkaChallenge(challenge)
                    return EapAkaResponse.respondToEapAkaChallenge(context, subscription, challenge2, realm).response()
                }

            }, carrierMccMnc, getImsiEap(
                telephonyManager.simOperator,
                telephonyManager.subscriberId,
                realm)!!, telephonyManager.imei)
            client.destroy()
        }

    }

}