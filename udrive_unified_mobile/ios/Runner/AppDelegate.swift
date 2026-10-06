import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps SDK key. Read from Info.plist so the key is not hard-coded
    // in source control; add a "GMSApiKey" String entry to Info.plist.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }
    GeneratedPluginRegistrant.register(with: self)

    // Keeps the screen on while a live ride is open (lib/core/services/screen_awake.dart).
    // A locked phone suspends the app, and with it the driver's live location.
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(name: "udrive/screen", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in
          if call.method == "keepOn" {
            let args = call.arguments as? [String: Any]
            UIApplication.shared.isIdleTimerDisabled = (args?["on"] as? Bool) ?? false
            result(nil)
          } else {
            result(FlutterMethodNotImplemented)
          }
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
