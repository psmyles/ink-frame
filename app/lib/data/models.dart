/// Rows members read directly (RLS SELECT); shapes follow the `Frame` schema in
/// shared/api/openapi.yaml and `public.frame` / `public.members`.
library;

enum Role { owner, member }

class Frame {
  const Frame({
    required this.id,
    required this.name,
    required this.modelId,
    required this.connected,
    required this.upToDate,
    required this.lastSeenAt,
    required this.batteryPct,
    required this.fwVersion,
    required this.imageIntervalS,
    required this.syncIntervalS,
    required this.timezone,
  });

  final String id;
  final String name;
  final String modelId;
  final bool connected;
  final bool upToDate;
  final DateTime? lastSeenAt;
  final int? batteryPct;
  final String? fwVersion;
  final int imageIntervalS;
  final int syncIntervalS;
  final String timezone;

  /// From a `public.frame` row or an app-api `Frame` object.
  factory Frame.fromJson(Map<String, dynamic> j) => Frame(
        id: j['id'] as String,
        name: j['name'] as String,
        modelId: j['model_id'] as String,
        connected: j['connected'] as bool? ?? j['hw_id'] != null,
        upToDate: j['up_to_date'] as bool,
        lastSeenAt: j['last_seen_at'] == null ? null : DateTime.parse(j['last_seen_at'] as String),
        batteryPct: j['battery_pct'] as int?,
        fwVersion: j['fw_version'] as String?,
        imageIntervalS: j['image_interval_s'] as int,
        syncIntervalS: j['sync_interval_s'] as int,
        timezone: j['timezone'] as String,
      );
}

class Member {
  const Member({required this.userId, required this.role, required this.displayName});

  final String userId;
  final Role role;
  final String displayName;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        userId: j['user_id'] as String,
        role: Role.values.byName(j['role'] as String),
        displayName: j['display_name'] as String,
      );
}

/// What Home shows for one frame.
class FrameSummary {
  const FrameSummary({required this.frame, required this.me, required this.owner});

  final Frame frame;
  final Member me;
  final Member owner;

  bool get isMine => me.role == Role.owner;
}
