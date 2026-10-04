import 'dart:convert';
import 'dart:typed_data';

/// The frame's Bluetooth pairing service (docs/pairing.md, shared/pairing.json).
abstract final class Pairing {
  static const namePrefix = 'InkFrame-';
  static const service = '42a40001-0087-4bd2-ab9b-8b4febd5191e';
  static const info = '42a40002-0087-4bd2-ab9b-8b4febd5191e';
  static const wifiScan = '42a40003-0087-4bd2-ab9b-8b4febd5191e';
  static const provision = '42a40004-0087-4bd2-ab9b-8b4febd5191e';
  static const status = '42a40005-0087-4bd2-ab9b-8b4febd5191e';
  static const maxMessageBytes = 1024;

  /// The MTU the app asks for; it works with whatever it gets.
  static const preferredMtu = 247;
}

/// The `XXXX` of `InkFrame-XXXX`, which the frame also shows on its screen.
String frameSuffix(String name) =>
    name.startsWith(Pairing.namePrefix) ? name.substring(Pairing.namePrefix.length) : name;

/// One message: a line of UTF-8 JSON ending in `\n`.
Uint8List encodeMessage(Map<String, Object?> message) => utf8.encode('${jsonEncode(message)}\n');

/// [bytes] in pieces of at most [size] bytes (MTU − 3), in order.
List<Uint8List> chunks(Uint8List bytes, int size) => [
      for (var i = 0; i < bytes.length; i += size) Uint8List.sublistView(bytes, i, (i + size).clamp(0, bytes.length)),
    ];

/// Joins notification chunks back into messages.
class MessageReader {
  final _buffer = BytesBuilder(copy: false);

  /// The messages [chunk] completes. Lines that aren't JSON objects, or are longer
  /// than [Pairing.maxMessageBytes], are dropped.
  List<Map<String, dynamic>> add(Uint8List chunk) {
    final out = <Map<String, dynamic>>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0a) continue;
      _buffer.add(Uint8List.sublistView(chunk, start, i));
      start = i + 1;
      final line = _buffer.takeBytes();
      if (line.length > Pairing.maxMessageBytes) continue;
      try {
        final m = jsonDecode(utf8.decode(line));
        if (m is Map<String, dynamic>) out.add(m);
      } on FormatException {
        // Not a message; skip it.
      }
    }
    _buffer.add(Uint8List.sublistView(chunk, start));
    if (_buffer.length > Pairing.maxMessageBytes) _buffer.clear();
    return out;
  }
}

/// The `info` characteristic.
class FrameInfo {
  const FrameInfo({required this.hwId, required this.modelId, required this.fwVersion, this.frameId, this.sd});

  final String hwId;
  final String modelId;
  final String fwVersion;

  /// The frame this hardware is linked to, or null.
  final String? frameId;

  /// The memory card; null from firmware that doesn't say (and pretend frames).
  final SdCard? sd;

  factory FrameInfo.fromJson(Map<String, dynamic> j) => FrameInfo(
        hwId: j['hw_id'] as String,
        modelId: j['model_id'] as String,
        fwVersion: j['fw_version'] as String? ?? '',
        frameId: j['frame_id'] as String?,
        sd: SdCard.fromJson(j['sd']),
      );

  Map<String, Object?> toJson() =>
      {'hw_id': hwId, 'model_id': modelId, 'fw_version': fwVersion, 'frame_id': frameId, if (sd != null) 'sd': sd!.toJson()};
}

enum SdState { ok, missing, unreadable }

/// The frame's memory card (`info.sd`): `unreadable` is one it can't read (not FAT, e.g.
/// exFAT as larger cards come, or damaged), which erasing fixes. Sizes only when `ok`.
class SdCard {
  const SdCard(this.state, {this.totalBytes = 0, this.freeBytes = 0, this.cacheBytes = 0, this.otherBytes = 0});

  final SdState state;
  final int totalBytes, freeBytes, cacheBytes, otherBytes;

  static SdCard? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final state = SdState.values.where((s) => s.name == j['state']).firstOrNull;
    if (state == null) return null;
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return SdCard(state,
        totalBytes: n('total_bytes'), freeBytes: n('free_bytes'), cacheBytes: n('cache_bytes'), otherBytes: n('other_bytes'));
  }

  Map<String, Object?> toJson() => {
        'state': state.name,
        if (state == SdState.ok) ...{
          'total_bytes': totalBytes,
          'free_bytes': freeBytes,
          'cache_bytes': cacheBytes,
          'other_bytes': otherBytes,
        },
      };
}

/// A network the frame can see (`wifi_scan`).
class WifiNetwork {
  const WifiNetwork(this.ssid, {this.rssi = -60, this.secure = true});

  final String ssid;
  final int rssi;
  final bool secure;

  factory WifiNetwork.fromJson(Map<String, dynamic> j) =>
      WifiNetwork(j['ssid'] as String, rssi: j['rssi'] as int? ?? -100, secure: j['secure'] as bool? ?? true);

  Map<String, Object?> toJson() => {'ssid': ssid, 'rssi': rssi, 'secure': secure};

  /// 0–3 bars.
  int get bars => rssi >= -55 ? 3 : rssi >= -67 ? 2 : rssi >= -78 ? 1 : 0;
}

/// What the app writes to `provision`.
class Provision {
  const Provision({
    required this.ssid,
    required this.password,
    required this.apiBaseUrl,
    required this.pairingToken,
    this.eraseSd = false,
  });

  final String ssid;
  final String password;
  final String apiBaseUrl;
  final String pairingToken;

  /// Format the memory card first (everything on it is lost).
  final bool eraseSd;

  Map<String, Object?> toJson() => {
        'ssid': ssid,
        'password': password,
        'api_base_url': apiBaseUrl,
        'pairing_token': pairingToken,
        if (eraseSd) 'erase_sd': true,
      };

  factory Provision.fromJson(Map<String, dynamic> j) => Provision(
        ssid: j['ssid'] as String,
        password: j['password'] as String,
        apiBaseUrl: j['api_base_url'] as String,
        pairingToken: j['pairing_token'] as String,
        eraseSd: j['erase_sd'] as bool? ?? false,
      );
}

enum LinkState { erasing, wifiConnecting, wifiFailed, claiming, claimed, syncing, ready, error }

/// A `status` notification.
class LinkStatus {
  const LinkStatus(this.state, {this.reason, this.code, this.message, this.frameId});

  final LinkState state;

  /// For [LinkState.wifiFailed]: `auth`, `not_found` or `other`.
  final String? reason;

  /// For [LinkState.error], e.g. `invalid_pairing_token` (docs/pairing.md).
  final String? code;
  final String? message;

  /// For [LinkState.claimed].
  final String? frameId;

  static const _states = {
    'erasing': LinkState.erasing,
    'wifi_connecting': LinkState.wifiConnecting,
    'wifi_failed': LinkState.wifiFailed,
    'claiming': LinkState.claiming,
    'claimed': LinkState.claimed,
    'syncing': LinkState.syncing,
    'ready': LinkState.ready,
    'error': LinkState.error,
  };

  /// Null for a state this app doesn't know (a newer frame); it's ignored.
  static LinkStatus? fromJson(Map<String, dynamic> j) {
    final state = _states[j['state']];
    if (state == null) return null;
    return LinkStatus(
      state,
      reason: j['reason'] as String?,
      code: j['code'] as String?,
      message: j['message'] as String?,
      frameId: j['frame_id'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'state': _states.entries.firstWhere((e) => e.value == state).key,
        'reason': ?reason,
        'code': ?code,
        'message': ?message,
        'frame_id': ?frameId,
      };
}
