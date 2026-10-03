import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/frame/frame_status.dart';
import 'package:ink_frame/widgets/formatting.dart';

Frame frame({int? battery, int? level = 20}) => Frame(
      id: 'f',
      name: 'Kitchen',
      modelId: 'm',
      connected: true,
      upToDate: true,
      lastSeenAt: DateTime.utc(2026, 10, 3, 10),
      batteryPct: battery,
      fwVersion: '1',
      imageIntervalS: 14400,
      syncIntervalS: 86400,
      timezone: 'UTC',
      lowBatteryPct: level,
    );

void main() {
  final now = DateTime.utc(2026, 10, 3, 12);

  test('low battery follows the frame\'s warning level; off means no warning', () {
    expect(FrameStatus.of(frame(battery: 15), now).lowBattery, 15);
    expect(FrameStatus.of(frame(battery: 25), now).lowBattery, isNull);
    expect(FrameStatus.of(frame(battery: 25, level: 30), now).lowBattery, 25);
    expect(FrameStatus.of(frame(battery: 5, level: null), now).lowBattery, isNull);
    expect(FrameStatus.of(frame(battery: null), now).lowBattery, isNull);
  });

  test('frames read the warning level from the table or the API, with a default before 0005', () {
    final row = {
      'id': 'f', 'name': 'K', 'model_id': 'm', 'hw_id': 'x', 'up_to_date': true, 'image_interval_s': 3600,
      'sync_interval_s': 3600, 'timezone': 'UTC', 'quiet_start': '22:00:00', 'quiet_end': '07:00:00',
    };
    expect(Frame.fromJson({...row, 'low_battery_pct': 30}).lowBatteryPct, 30);
    expect(Frame.fromJson({...row, 'low_battery_pct': null}).lowBatteryPct, isNull);
    expect(Frame.fromJson(row).lowBatteryPct, 20);
    expect((Frame.fromJson(row).quietStart, Frame.fromJson(row).quietEnd), ('22:00', '07:00'));
  });

  test('sizes and intervals in plain words', () {
    const en = Locale('en');
    expect(formatBytes(312 * 1024 * 1024, en), '312 MB');
    expect(formatBytes(1024 * 1024 * 1024, en), '1 GB');
    expect(formatBytes((1.4 * 1024 * 1024 * 1024).round(), en), '1.4 GB');
    expect(formatBytes(57 * 1024, en), '57 KB');
    expect(timeZoneParts('America/New_York'), ('New York', 'America'));
    expect(timeZoneParts('America/Argentina/Buenos_Aires'), ('Buenos Aires', 'America/Argentina'));
    expect(timeZoneParts('UTC'), ('UTC', ''));
  });
}
