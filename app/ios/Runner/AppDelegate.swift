import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Low-battery notifications also show while the app is open.
    UNUserNotificationCenter.current().delegate = self
    // The background battery check (lib/battery/background.dart); must be registered
    // before launch finishes. Same identifier as Info.plist and the Dart side.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.psmyles.inkframe.battery", earliestBeginInSeconds: NSNumber(value: 6 * 60 * 60))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Plugins (secure storage, notifications) for the background check's engine.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
  }
}
