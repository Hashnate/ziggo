import Flutter
import UIKit
import GoogleMaps
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Safe Firebase configuration: verify plist exists and avoid duplicate configuration crashes
    if FirebaseApp.app() == nil {
      if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
         FileManager.default.fileExists(atPath: plistPath) {
        FirebaseApp.configure()
      } else {
        NSLog("[ios-startup] GoogleService-Info.plist not found in bundle — skipping Firebase configure")
      }
    }

    application.registerForRemoteNotifications() // Force APNs registration on boot

    // Guaranteed Google Maps initialization: always provide a key to prevent GMSInvalidAPIKeyException crash
    let fallbackMapsKey = "AIzaSyAFtdjwK5SdMdo7c4F7jvJHWE-OE2LDSCk"
    var mapsKey = fallbackMapsKey
    if let key = Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY") as? String,
       !key.isEmpty,
       !key.contains("$") {
      mapsKey = key
    }
    GMSServices.provideAPIKey(mapsKey)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let errorMessage = "Failed to register for remote notifications: \(error.localizedDescription)"
    NSLog(errorMessage)
    
    // Post the error message back to the backend so we can see it in docker compose logs
    let hosts = ["https://ziggo.lk"]
    for host in hosts {
      if let url = URL(string: "\(host)/api/v1/public/log") {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let json: [String: Any] = ["message": "[ios-native-error] \(errorMessage)"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        URLSession.shared.dataTask(with: request).resume()
      }
    }
    
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
