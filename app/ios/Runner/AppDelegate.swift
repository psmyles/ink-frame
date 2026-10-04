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
    // Photos shared from other apps: where the share extension leaves them
    // (ShareExtension/ShareViewController.swift, lib/data/shared_inbox.dart).
    let share = FlutterMethodChannel(name: "inkframe/share", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    share.setMethodCallHandler { call, result in
      guard call.method == "inbox" else { return result(FlutterMethodNotImplemented) }
      let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.psmyles.inkframe")
      result(container?.appendingPathComponent("share-inbox", isDirectory: true).path)
    }
    // Plugins (secure storage, notifications) for the background check's engine.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
  }
}
