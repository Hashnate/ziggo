import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Key flows: ios/Flutter/Secrets.xcconfig (gitignored) -> Info.plist
    // ($(MAPS_API_KEY) substitution) -> here. Never hardcoded in source.
    if let key = Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY") as? String,
       !key.isEmpty {
      GMSServices.provideAPIKey(key)
    } else {
      NSLog("MAPS_API_KEY missing — add it to ios/Flutter/Secrets.xcconfig")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
