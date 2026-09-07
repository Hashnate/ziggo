package lk.ziggo.app

import android.os.Bundle
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
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            referrerClient = InstallReferrerClient.newBuilder(this).build()
            referrerClient?.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (responseCode == InstallReferrerClient.InstallReferrerResponseCode.OK) {
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
