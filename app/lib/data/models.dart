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
    this.displayOrder = 'random',
    this.quietStart,
    this.quietEnd,
    this.lowBatteryPct = 20,
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

  /// `random` (shuffle) or `sequential` (in order).
  final String displayOrder;

  /// Quiet hours as `HH:MM` local to [timezone]; both set or both null.
  final String? quietStart, quietEnd;

  /// Warn below this battery percentage; null = no warning (app-only setting).
  final int? lowBatteryPct;

  bool get inOrder => displayOrder == 'sequential';
  bool get hasQuietHours => quietStart != null && quietEnd != null;

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
        displayOrder: j['display_order'] as String? ?? 'random',
        quietStart: _hhmm(j['quiet_start']),
        quietEnd: _hhmm(j['quiet_end']),
        // A project from before the battery warning (0005) has no column: the default.
        lowBatteryPct: j.containsKey('low_battery_pct') ? j['low_battery_pct'] as int? : 20,
      );

  /// `22:00` from the API, `22:00:00` from the table.
  static String? _hhmm(Object? v) => v == null ? null : (v as String).substring(0, 5);
}

class Member {
  const Member({required this.userId, required this.role, required this.displayName, this.joinedAt});

  final String userId;
  final Role role;
  final String displayName;
  final DateTime? joinedAt;

  bool get isOwner => role == Role.owner;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        userId: j['user_id'] as String,
        role: Role.values.byName(j['role'] as String),
        displayName: j['display_name'] as String,
        joinedAt: j['created_at'] == null ? null : DateTime.parse(j['created_at'] as String),
      );
}

/// An active invite (`public.invites`, owner only). The code itself is only shown
/// once, when it's created ([NewInvite]).
class Invite {
  const Invite({required this.id, required this.expiresAt, required this.maxUses, required this.uses});

  final String id;
  final DateTime expiresAt;
  final int maxUses, uses;

  factory Invite.fromJson(Map<String, dynamic> j) => Invite(
        id: j['id'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        maxUses: j['max_uses'] as int,
        uses: j['uses'] as int,
      );
}

/// `POST /invites`: the code, returned just this once.
class NewInvite {
  const NewInvite({required this.id, required this.code, required this.expiresAt, required this.maxUses});

  final String id;
  final String code;
  final DateTime expiresAt;
  final int maxUses;

  factory NewInvite.fromJson(Map<String, dynamic> j) => NewInvite(
        id: j['invite_id'] as String,
        code: j['code'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        maxUses: j['max_uses'] as int,
      );
}

/// Photos and bytes against limits (`GET /usage`); a null limit is unlimited.
class UsageEntry {
  const UsageEntry({required this.images, required this.bytes, this.maxImages, this.maxBytes, this.userId});

  final int images, bytes;
  final int? maxImages, maxBytes;

  /// Null for the frame's total.
  final String? userId;

  factory UsageEntry.fromJson(Map<String, dynamic> j) => UsageEntry(
        images: j['images'] as int,
        bytes: (j['bytes'] as num).toInt(),
        maxImages: j['max_images'] as int?,
        maxBytes: (j['max_bytes'] as num?)?.toInt(),
        userId: j['user_id'] as String?,
      );
}

class Usage {
  const Usage({required this.frame, required this.freeTierBytes, required this.users});

  final UsageEntry frame;

  /// Supabase's free storage (1 GB), shown when the frame has no byte limit.
  final int freeTierBytes;

  /// Everyone for the owner; just you for others.
  final List<UsageEntry> users;

  /// The limit the bar is drawn against.
  int get limitBytes => frame.maxBytes ?? freeTierBytes;
  double get fraction => limitBytes == 0 ? 0 : (frame.bytes / limitBytes).clamp(0.0, 1.0);
  bool get nearlyFull => fraction >= 0.8;
  bool get full =>
      (frame.maxBytes != null && frame.bytes >= frame.maxBytes!) ||
      (frame.maxImages != null && frame.images >= frame.maxImages!);

  factory Usage.fromJson(Map<String, dynamic> j) {
    final f = j['frame'] as Map<String, dynamic>;
    return Usage(
      frame: UsageEntry.fromJson(f),
      freeTierBytes: (f['free_tier_bytes'] as num).toInt(),
      users: [for (final u in j['users'] as List) UsageEntry.fromJson(u as Map<String, dynamic>)],
    );
  }
}

/// What Home shows for one frame.
class FrameSummary {
  const FrameSummary({required this.frame, required this.me, required this.owner});

  final Frame frame;
  final Member me;
  final Member owner;

  bool get isMine => me.role == Role.owner;
}

/// A ready photo on the frame (`public.images`).
class FrameImage {
  const FrameImage({
    required this.id,
    required this.uploadedBy,
    required this.storagePath,
    required this.bytes,
    required this.position,
    required this.createdAt,
  });

  final String id;

  /// Null once the uploader deleted their account.
  final String? uploadedBy;
  final String storagePath;
  final int bytes;
  final double position;
  final DateTime createdAt;

  factory FrameImage.fromJson(Map<String, dynamic> j) => FrameImage(
        id: j['id'] as String,
        uploadedBy: j['uploaded_by'] as String?,
        // app-api's Image leaves it out; objects are always `{id}.png`.
        storagePath: j['storage_path'] as String? ?? '${j['id']}.png',
        bytes: j['bytes'] as int,
        position: (j['position'] as num).toDouble(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  @override
  bool operator ==(Object other) => other is FrameImage && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A panel model with its palette (`public.device_models` + `public.palettes`).
class DeviceModel {
  const DeviceModel({required this.id, required this.name, required this.width, required this.height, required this.palette});

  final String id;
  final String name;
  final int width, height;

  /// `{id, colors: [{name, color, deviceColor}]}`, as `Palette.fromJson` reads it.
  final Map<String, dynamic> palette;

  factory DeviceModel.fromJson(Map<String, dynamic> j) => DeviceModel(
        id: j['id'] as String,
        name: j['name'] as String,
        width: j['width'] as int,
        height: j['height'] as int,
        palette: {'id': j['palette_id'], 'colors': (j['palettes'] as Map<String, dynamic>)['colors']},
      );
}
