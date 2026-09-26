import '../../data/models.dart';

enum StatusKind { upToDate, changesWaiting, firstCheck, notConnected, notCheckedIn }

/// The one-line status for a frame (app-flow §4.2), before wording.
class FrameStatus {
  const FrameStatus(this.kind, {this.lastSeen, this.nextCheck, this.lowBattery});

  final StatusKind kind;
  final DateTime? lastSeen;

  /// When the frame should check next; null if it's already overdue.
  final DateTime? nextCheck;

  /// Battery percentage when below [lowBatteryPct].
  final int? lowBattery;

  static const lowBatteryPct = 20;

  bool get isWarning => kind == StatusKind.notCheckedIn || lowBattery != null;

  factory FrameStatus.of(Frame f, DateTime now) {
    final battery = (f.batteryPct != null && f.batteryPct! < lowBatteryPct) ? f.batteryPct : null;
    if (!f.connected) return const FrameStatus(StatusKind.notConnected);
    final seen = f.lastSeenAt;
    if (seen == null) return FrameStatus(StatusKind.firstCheck, lowBattery: battery);

    final interval = Duration(seconds: f.syncIntervalS);
    if (now.difference(seen) > interval * 2) {
      return FrameStatus(StatusKind.notCheckedIn, lastSeen: seen, lowBattery: battery);
    }
    final next = seen.add(interval);
    return FrameStatus(
      f.upToDate ? StatusKind.upToDate : StatusKind.changesWaiting,
      lastSeen: seen,
      nextCheck: next.isAfter(now) ? next : null,
      lowBattery: battery,
    );
  }
}
