import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NSLog("ZIGGO_DIAG didFinishLaunching: start")
    if let key = Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY") as? String,
       !key.isEmpty,
       !key.contains("$") {
      GMSServices.provideAPIKey(key)
    } else {
      NSLog("ZIGGO_DIAG MAPS_API_KEY missing or invalid — add it to ios/Flutter/Secrets.xcconfig")
    }
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // TEMP DIAGNOSTIC (remove once the white screen is fixed): after the scene
    // should have connected, report whether a window exists and what its root
    // view controller is. A nil root, or a root that is NOT a FlutterViewController,
    // is what produces a white screen.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
      let scenes = application.connectedScenes
      NSLog("ZIGGO_DIAG connectedScenes count=\(scenes.count)")
      for scene in scenes {
        if let ws = scene as? UIWindowScene {
          NSLog("ZIGGO_DIAG windowScene state=\(ws.activationState.rawValue) windows=\(ws.windows.count)")
          for w in ws.windows {
            NSLog("ZIGGO_DIAG window isKey=\(w.isKeyWindow) hidden=\(w.isHidden) rootVC=\(String(describing: w.rootViewController))")
          }
        }
      }
    }

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    NSLog("ZIGGO_DIAG didInitializeImplicitFlutterEngine: registering plugins")
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
