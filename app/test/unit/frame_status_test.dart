import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/frame/frame_status.dart';

final now = DateTime.utc(2026, 9, 26, 12);

Frame frame({bool connected = true, bool upToDate = true, Duration? seenAgo = const Duration(hours: 3), int? battery = 80}) =>
    Frame(
      id: 'f',
      name: 'Kitchen',
      modelId: 'reterminal-e1002',
      connected: connected,
      upToDate: upToDate,
      lastSeenAt: seenAgo == null ? null : now.subtract(seenAgo),
      batteryPct: battery,
      fwVersion: '1.0.0',
      imageIntervalS: 14400,
      syncIntervalS: 86400,
      timezone: 'Europe/Berlin',
    );

void main() {
  test('up to date', () {
    final s = FrameStatus.of(frame(), now);
    expect(s.kind, StatusKind.upToDate);
    expect(s.lastSeen, now.subtract(const Duration(hours: 3)));
    expect(s.isWarning, isFalse);
  });

  test('changes waiting, with the next check', () {
    final s = FrameStatus.of(frame(upToDate: false), now);
    expect(s.kind, StatusKind.changesWaiting);
    expect(s.nextCheck, now.add(const Duration(hours: 21)));
  });

  test('next check already due', () {
    final s = FrameStatus.of(frame(upToDate: false, seenAgo: const Duration(hours: 30)), now);
    expect(s.kind, StatusKind.changesWaiting);
    expect(s.nextCheck, isNull);
  });

  test('not checked in for more than twice the interval', () {
    final s = FrameStatus.of(frame(seenAgo: const Duration(hours: 49)), now);
    expect(s.kind, StatusKind.notCheckedIn);
    expect(s.isWarning, isTrue);
  });

  test('not connected, and connected but never checked', () {
    expect(FrameStatus.of(frame(connected: false, seenAgo: null), now).kind, StatusKind.notConnected);
    expect(FrameStatus.of(frame(seenAgo: null), now).kind, StatusKind.firstCheck);
  });

  test('low battery', () {
    expect(FrameStatus.of(frame(battery: 15), now).lowBattery, 15);
    expect(FrameStatus.of(frame(battery: 20), now).lowBattery, isNull);
    expect(FrameStatus.of(frame(battery: null), now).lowBattery, isNull);
  });
}
