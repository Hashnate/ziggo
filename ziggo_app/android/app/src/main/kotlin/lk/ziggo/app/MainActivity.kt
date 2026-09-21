package lk.ziggo.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "lk.ziggo.app/install_referrer"
    private var referrerUrl: String? = null
    private var referrerClient: InstallReferrerClient? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInstallReferrer") {
                result.success(referrerUrl)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lk.ziggo.app/floating_widget").setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> {
                    val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(canDraw)
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PERMISSION_ERROR", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "showFloatingWidget" -> {
                    FloatingWidgetService.show(this)
                    result.success(true)
                }
                "hideFloatingWidget" -> {
                    FloatingWidgetService.hide(this)
                    result.success(true)
                }
                "isFloatingWidgetShowing" -> {
                    result.success(FloatingWidgetService.isShowing)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
        try {
            referrerClient = InstallReferrerClient.newBuilder(this).build()
            referrerClient?.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        try {
                            val response = referrerClient?.installReferrer
                            referrerUrl = response?.installReferrer
                        } catch (e: Exception) {
                            // ignore
                        }
                    }
                    try {
                        referrerClient?.endConnection()
                    } catch (e: Exception) {
                        // ignore
                    }
                }

                override fun onInstallReferrerServiceDisconnected() {
                    // Try to reconnect if needed
                }
            })
        } catch (e: Exception) {
            // Safe fallback if Google Play services are missing or disabled
        }
    }
}
