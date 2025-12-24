package com.example.audiocom_app

import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.audiocom_app/screen_share"
    private val SCREEN_CAPTURE_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    // Deprecated: Direct start is risky on Android 14+ without token.
                    // Use requestPermission instead.
                    startScreenShareService()
                    result.success(null)
                }
                "requestPermission" -> {
                    // 1. Trigger System Dialog
                    val mediaProjectionManager = getSystemService(android.content.Context.MEDIA_PROJECTION_SERVICE) as android.media.projection.MediaProjectionManager
                    startActivityForResult(mediaProjectionManager.createScreenCaptureIntent(), SCREEN_CAPTURE_REQUEST_CODE)
                    pendingResult = result
                }
                "stopService" -> {
                    val intent = Intent(this, ScreenShareService::class.java)
                    stopService(intent)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startScreenShareService() {
        val intent = Intent(this, ScreenShareService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREEN_CAPTURE_REQUEST_CODE) {
            if (resultCode == android.app.Activity.RESULT_OK) {
                // 2. Permission Granted -> Start Service IMMEDIATELY
                startScreenShareService()
                pendingResult?.success(true)
            } else {
                // Denied
                pendingResult?.success(false)
            }
            pendingResult = null
        }
    }
}
