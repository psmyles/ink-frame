import 'dart:io';
import 'dart:ui';

import 'package:workmanager/workmanager.dart';

import '../data/secure_store.dart';
import '../l10n/app_localizations.dart';
import 'battery_watch.dart';
import 'notifications.dart';

/// Also the iOS BGTaskScheduler identifier (Info.plist, AppDelegate.swift).
const batteryTask = 'com.psmyles.inkframe.battery';

/// Runs in the background (Android WorkManager, iOS background refresh): checks the
/// watched frames and notifies about the ones whose battery just went low.
@pragma('vm:entry-point')
void batteryCheckDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      await checkBatteries(BatteryWatch(SecureStore.background()), Notifications());
      return true;
    } catch (_) {
      return false; // the OS tries again later
    }
  });
}

Future<void> checkBatteries(BatteryWatch watch, Notifications notifications) async {
  final low = await watch.check();
  if (low.isEmpty) return;
  final l = lookupAppLocalizations(_locale());
  for (final f in low) {
    await notifications.show(
      f.address.url.hashCode & 0x7fffffff,
      l.batteryLowTitle(f.name),
      l.batteryLowBody(f.batteryPct),
      channel: l.batteryChannel,
    );
  }
}

Locale _locale() {
  final l = PlatformDispatcher.instance.locale;
  return AppLocalizations.supportedLocales.any((s) => s.languageCode == l.languageCode) ? Locale(l.languageCode) : const Locale('en');
}

/// Schedules the check every few hours (phones only). Battery is reported at each
/// of the frame's daily checks, so a few times a day is plenty.
Future<void> scheduleBatteryChecks() async {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  await Workmanager().initialize(batteryCheckDispatcher);
  await Workmanager().registerPeriodicTask(
    batteryTask,
    batteryTask,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
