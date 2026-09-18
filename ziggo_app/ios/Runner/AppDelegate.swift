import Flutter
import UIKit
import GoogleMaps
import FirebaseCore
import FirebaseMessaging
import PushKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    application.registerForRemoteNotifications() // Force APNs registration on boot

    // PushKit: the VoIP channel that lets a ride offer ring like a real call.
    // Separate token and separate APNs topic (<bundle>.voip) from the FCM one.
    let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [PKPushType.voIP]
    
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

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      data,
      fromPushKit: true
    )
    completion()
  }
}
