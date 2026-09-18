import Flutter
import Foundation
import UIKit
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import PushKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  // MUST be retained for the app's lifetime. PushKit delivers the VoIP token
  // (and every push) to this exact object asynchronously; if it's a local that
  // dies when didFinishLaunching returns, the system's callback lands on freed
  // memory and the app crashes seconds after launch.
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    application.registerForRemoteNotifications() // Force APNs registration on boot

    // PushKit: the VoIP channel that lets a ride offer ring like a real call.
    // Separate token and separate APNs topic (<bundle>.voip) from the FCM one.
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [PKPushType.voIP]
    voipRegistry = registry
    
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
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data
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

  // MARK: - PushKit (VoIP)

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    let deviceToken = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    // Hand it to the plugin; Dart reads it via getDevicePushTokenVoIP() and
    // PUTs it to /api/v1/auth/voip-token.
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
    // Breadcrumb to the backend: proves the registry survived long enough for
    // PushKit to call back. If this line never appears in server logs after an
    // iOS launch, the registry is being freed before the token arrives.
    postNativeLog("[ios-native] voip token received (\(deviceToken.count) chars)")
  }

  private func postNativeLog(_ message: String) {
    guard let url = URL(string: "https://ziggo.lk/api/v1/public/log") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["message": message])
    URLSession.shared.dataTask(with: request).resume()
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    // iOS 13+ REQUIRES that every VoIP push reports a call to CallKit before
    // this returns. Failing to do so gets the app killed and, after repeat
    // offences, cut off from VoIP pushes entirely — so this path must never
    // bail out early, even on a malformed payload.
    let dict = payload.dictionaryPayload
    let id = dict["id"] as? String ?? UUID().uuidString
    let nameCaller = dict["nameCaller"] as? String ?? "Ziggo"
    let handle = dict["handle"] as? String ?? "New ride request"
    // Data.extra is an NSDictionary, so read it as one rather than bridging.
    let extra = (dict["extra"] as? NSDictionary) ?? NSDictionary()

    let data = flutter_callkit_incoming.Data(
      id: id,
      nameCaller: nameCaller,
      handle: handle,
      type: 0
    )
    data.extra = extra
    data.duration = 30000 // matches the backend's 30 s accept window

    if let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
      plugin.showCallkitIncoming(data, fromPushKit: true)
    } else {
      // Plugin not registered yet (engine still booting). Surface it loudly —
      // an unreported VoIP push is exactly what gets an app terminated.
      NSLog("[callkit] VoIP push arrived before plugin registration — call NOT reported")
    }
    completion()
  }
}
