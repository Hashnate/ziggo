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
    FirebaseApp.configure()
    application.registerForRemoteNotifications() // Force APNs registration on boot
    
    if let key = Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY") as? String,
       !key.isEmpty,
       !key.contains("$") {
      GMSServices.provideAPIKey(key)
    } else {
      NSLog("MAPS_API_KEY missing or invalid — add it to ios/Flutter/Secrets.xcconfig")
    }
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
    let hosts = ["https://ziggo.lk", "http://187.127.152.141"]
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
