import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications (phones): permission and showing one. Used for the
/// low-battery notification only.
class Notifications {
  Notifications([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  var _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Asked for when someone turns the notification on, not at start.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  /// Whether Ink Frame may show notifications on this phone.
  Future<bool> allowed() async {
    await _init();
    if (Platform.isAndroid) return await _android?.areNotificationsEnabled() ?? false;
    if (Platform.isIOS) return (await _ios?.checkPermissions())?.isEnabled ?? false;
    return false;
  }

  /// Asks (once; after that the OS answers without asking). True when allowed.
  Future<bool> request() async {
    await _init();
    if (Platform.isAndroid) return await _android?.requestNotificationsPermission() ?? false;
    if (Platform.isIOS) return await _ios?.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  Future<void> show(int id, String title, String body, {required String channel}) async {
    await _init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails('battery', channel),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
