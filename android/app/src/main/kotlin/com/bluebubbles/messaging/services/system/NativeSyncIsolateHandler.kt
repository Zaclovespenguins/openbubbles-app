package com.bluebubbles.messaging.services.system

import android.content.Context
import android.util.Log
import com.bluebubbles.messaging.Constants
import com.bluebubbles.messaging.models.MethodCallHandlerImpl
import com.bluebubbles.messaging.services.backend_ui_interop.MethodCallHandler
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.ApplicationInfoLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import io.flutter.view.FlutterMain
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class NativeSyncIsolateHandler : MethodCallHandlerImpl() {
    companion object {
        const val tag = "native-sync-isolate"
    }

    override fun handleMethodCall(
        call: MethodCall,
        mainresult: MethodChannel.Result,
        mainContext: Context
    ) {
        val context = mainContext.applicationContext
        FlutterMain.startInitialization(context)
        FlutterMain.ensureInitializationComplete(context, null)

        Log.d(Constants.logTag, "Loading callback info")
        val info = ApplicationInfoLoader.load(context)
        val workerEngine = FlutterEngine(context)
        MethodChannel(workerEngine.dartExecutor.binaryMessenger, Constants.methodChannel).setMethodCallHandler {
                call, result -> run {
            if (call.method == "ready") {
                Log.d(Constants.logTag, "Dart engine is ready!")
                mainresult.success(null)
            } else if (call.method == "exit") {
                workerEngine.destroy()
            } else {
                MethodCallHandler().methodCallHandler(call, result, context)
            }
        }
        }
        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(context.getSharedPreferences("FlutterSharedPreferences", 0).getLong("flutter.backgroundSyncIsolate", -1))
        val callback = DartExecutor.DartCallback(context.assets, info.flutterAssetsDir, callbackInfo)

        Log.d(Constants.logTag, "Executing Dart callback")
        workerEngine.dartExecutor.executeDartCallback(callback)
    }
}