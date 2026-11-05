package lk.ziggo.app

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "lk.ziggo.app/install_referrer"
    private var referrerUrl: String? = null
    private var referrerClient: InstallReferrerClient? = null

    private val LOCATION_CHANNEL = "lk.ziggo.app/location_intent"
    private var locationMethodChannel: MethodChannel? = null
    private var pendingLocationUri: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        locationMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLocation" -> {
                        val uri = pendingLocationUri
                        pendingLocationUri = null
                        result.success(uri)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
        }

        pendingLocationUri?.let { uri ->
            locationMethodChannel?.invokeMethod("onLocationReceived", uri)
        }

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
                            try {
                                val fallbackIntent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                                startActivity(fallbackIntent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("PERMISSION_ERROR", e2.message, null)
                            }
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lk.ziggo.app/file_downloader").setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val fileName = call.argument<String>("fileName") ?: "invoice.pdf"
                    val bytes = call.argument<ByteArray>("bytes")
                    val mimeType = call.argument<String>("mimeType") ?: "application/pdf"

                    if (bytes == null) {
                        result.error("INVALID_ARGS", "Bytes cannot be null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        var savedPath: String? = null
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val contentValues = ContentValues().apply {
                                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                            }
                            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                            if (uri != null) {
                                contentResolver.openOutputStream(uri)?.use { outputStream ->
                                    outputStream.write(bytes)
                                }
                                savedPath = "Downloads/$fileName"
                            }
                        } else {
                            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            if (!downloadsDir.exists()) {
                                downloadsDir.mkdirs()
                            }
                            val file = File(downloadsDir, fileName)
                            file.outputStream().use { outputStream ->
                                outputStream.write(bytes)
                            }
                            MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mimeType), null)
                            savedPath = file.absolutePath
                        }

                        if (savedPath != null) {
                            result.success(savedPath)
                        } else {
                            result.error("SAVE_FAILED", "Failed to create file in Downloads", null)
                        }
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        extractAndQueueLocationIntent(intent)
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractAndQueueLocationIntent(intent)
    }

    private fun extractAndQueueLocationIntent(intent: Intent?) {
        val uri: Uri = intent?.data ?: return
        val scheme = uri.scheme?.lowercase() ?: return
        val host = uri.host?.lowercase() ?: ""

        val isGeo = scheme == "geo" || scheme == "google.navigation"
        val isMapsUrl = (scheme == "http" || scheme == "https") &&
                (host == "maps.google.com" || host == "maps.app.goo.gl" || (host == "goo.gl" && uri.path?.startsWith("/maps") == true))

        if (isGeo || isMapsUrl) {
            val uriString = uri.toString()
            if (locationMethodChannel != null) {
                locationMethodChannel?.invokeMethod("onLocationReceived", uriString)
            } else {
                pendingLocationUri = uriString
            }
        }
    }
}
