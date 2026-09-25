/// A simulated Ink Frame: the device side of `device-api` (PLAN.md §7.3) with the
/// firmware's cache layout and sync rules (§9.3, §9.4), so the backend and the app
/// can be exercised before the hardware firmware exists.
///
/// State lives in one directory:
/// ```text
///   config.json          api_base_url, hw_id, frame_id, device_secret, settings…
///   cache/<id>.png       mirrored images
///   cache/manifest.txt   "id sha256 bytes position" per line (tmp file + rename)
///   cache/tmp/           downloads in progress; never shown
/// ```
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const fwVersion = 'sim-0.1.0';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
  @override
  String toString() => '$status $code: $message';
}

/// One line of cache/manifest.txt.
class CachedImage {
  CachedImage(this.id, this.sha256, this.bytes, this.position);
  final String id;
  final String sha256;
  final int bytes;
  final double position;

  String toLine() => '$id $sha256 $bytes $position';

  static CachedImage? parse(String line) {
    final p = line.trim().split(' ');
    if (p.length != 4) return null;
    final bytes = int.tryParse(p[2]);
    final position = double.tryParse(p[3]);
    if (bytes == null || position == null) return null;
    return CachedImage(p[0], p[1], bytes, position);
  }
}

class SyncReport {
  SyncReport({
    required this.manifestVersion,
    required this.manifestChanged,
    this.added = const [],
    this.removed = const [],
    this.failed = const [],
    this.total = 0,
  });
  final int manifestVersion;
  final bool manifestChanged;
  final List<String> added;
  final List<String> removed;
  final List<String> failed;
  final int total;
}

class Frame {
  Frame(this.dir, {http.Client? client}) : _http = client ?? http.Client();

  final Directory dir;
  final http.Client _http;
  Map<String, dynamic> config = {};

  File get _configFile => File('${dir.path}/config.json');
  Directory get cacheDir => Directory('${dir.path}/cache');
  File get _manifestFile => File('${cacheDir.path}/manifest.txt');

  bool get isPaired => config['device_secret'] != null && config['api_base_url'] != null;

  Future<void> load() async {
    await cacheDir.create(recursive: true);
    if (await _configFile.exists()) {
      config = jsonDecode(await _configFile.readAsString()) as Map<String, dynamic>;
    }
    // A stable hardware id, like the ESP32 MAC: kept across re-pairing.
    config['hw_id'] ??= 'sim-${_hex(6)}';
    config['model_id'] ??= 'reterminal-e1002';
    await save();
  }

  Future<void> save() => _writeAtomic(_configFile, const JsonEncoder.withIndent('  ').convert(config));

  // ── Pairing ─────────────────────────────────────────────────────────────────

  /// POST /device-api/claim. The cache is kept until the claim succeeds (§9.4).
  Future<String> claim({required String apiBaseUrl, required String pairingToken, String? modelId}) async {
    final base = apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final body = await _post('$base/device-api/claim', {
      'pairing_token': pairingToken,
      'hw_id': config['hw_id'],
      'model_id': modelId ?? config['model_id'],
      'fw_version': fwVersion,
    });
    final sameFrame = body['frame_id'] == config['frame_id'];
    config
      ..['api_base_url'] = base
      ..['model_id'] = modelId ?? config['model_id']
      ..['frame_id'] = body['frame_id']
      ..['device_secret'] = body['device_secret'];
    if (!sameFrame) {
      // A different frame (e.g. another family space): start from an empty cache.
      await _wipeCache();
      config.remove('manifest_version');
    }
    await save();
    return body['frame_id'] as String;
  }

  // ── Sync ────────────────────────────────────────────────────────────────────

  /// POST /device-api/sync, then mirror the manifest into the cache exactly.
  /// With [force], asks for the full list (manifest_version 0), as the firmware does
  /// when its cache can't be trusted.
  Future<SyncReport> sync({bool force = false}) async {
    if (!isPaired) throw StateError('Not paired. Run `claim` first.');
    final cached = await readManifest();
    final localIds = [
      for (final c in cached)
        if (await _cachedFileOk(c)) c.id,
    ];
    final int since = force || cached.isEmpty && config['manifest_version'] == null
        ? 0
        : (config['manifest_version'] as int? ?? 0);

    final Map<String, dynamic> body;
    try {
      body = await _post('${config['api_base_url']}/device-api/sync', {
        'manifest_version': since,
        'fw_version': fwVersion,
        'battery_pct': 100,
        'rssi': -50,
        'sd_free_bytes': null,
        'local_ids': localIds,
      }, bearer: config['device_secret'] as String);
    } on ApiException catch (e) {
      if (e.status == 410) await _removed();
      rethrow;
    }

    config['settings'] = body['settings'];
    config['last_sync_at'] = DateTime.now().toUtc().toIso8601String();
    final version = body['manifest_version'] as int;
    final images = body['images'] as List<dynamic>?;
    if (images == null) {
      config['manifest_version'] = version;
      await save();
      return SyncReport(manifestVersion: version, manifestChanged: false, total: cached.length);
    }

    final tmp = Directory('${cacheDir.path}/tmp');
    await tmp.create(recursive: true);
    final added = <String>[], failed = <String>[];
    final kept = <CachedImage>[];
    for (final raw in images.cast<Map<String, dynamic>>()) {
      final img = CachedImage(raw['id'] as String, raw['sha256'] as String, raw['bytes'] as int,
          (raw['position'] as num).toDouble());
      if (localIds.contains(img.id)) {
        kept.add(img);
        continue;
      }
      final url = raw['url'] as String?;
      if (url != null && await _download(url, img, tmp)) {
        kept.add(img);
        added.add(img.id);
      } else {
        failed.add(img.id);
      }
    }

    // Mirror: anything not in the manifest goes.
    final keepIds = {for (final k in kept) k.id};
    final removed = <String>[];
    await for (final f in cacheDir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is File && name.endsWith('.png') && !keepIds.contains(name.replaceAll('.png', ''))) {
        await f.delete();
        removed.add(name.replaceAll('.png', ''));
      }
    }
    kept.sort((a, b) => a.position.compareTo(b.position));
    await _writeAtomic(_manifestFile, kept.map((k) => k.toLine()).join('\n'));

    // Only advance when everything arrived, so the next sync retries the rest.
    if (failed.isEmpty) config['manifest_version'] = version;
    if (added.isNotEmpty) config['newest_first'] = added;
    await save();
    return SyncReport(
      manifestVersion: version,
      manifestChanged: true,
      added: added,
      removed: removed,
      failed: failed,
      total: kept.length,
    );
  }

  Future<List<CachedImage>> readManifest() async {
    if (!await _manifestFile.exists()) return [];
    return (await _manifestFile.readAsLines()).map(CachedImage.parse).whereType<CachedImage>().toList();
  }

  File imageFile(String id) => File('${cacheDir.path}/$id.png');

  // ── Showing ─────────────────────────────────────────────────────────────────

  /// Picks the image to show next, like the firmware's pickNextImage: images that
  /// just arrived first, then sequential or random per settings.
  Future<CachedImage?> pickNext({bool previous = false, Random? random}) async {
    final images = await readManifest();
    if (images.isEmpty) return null;
    final byId = {for (final i in images) i.id: i};

    final newest = (config['newest_first'] as List<dynamic>? ?? []).cast<String>().where(byId.containsKey).toList();
    CachedImage pick;
    if (newest.isNotEmpty) {
      pick = byId[newest.removeLast()]!;
      config['newest_first'] = newest;
    } else if ((config['settings']?['display_order'] ?? 'random') == 'sequential') {
      final n = images.length;
      final current = (config['sequential_index'] as int? ?? -1);
      final next = ((previous ? current - 1 : current + 1) % n + n) % n;
      config['sequential_index'] = next;
      pick = images[next];
    } else {
      final rng = random ?? Random();
      final last = config['last_image_id'];
      final choices = images.length > 1 ? images.where((i) => i.id != last).toList() : images;
      pick = choices[rng.nextInt(choices.length)];
    }
    config['last_image_id'] = pick.id;
    await save();
    return pick;
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  Future<bool> _cachedFileOk(CachedImage c) async {
    final f = imageFile(c.id);
    return await f.exists() && await f.length() == c.bytes;
  }

  Future<bool> _download(String url, CachedImage img, Directory tmp) async {
    try {
      final res = await _http.get(Uri.parse(url));
      if (res.statusCode != 200) return false;
      final bytes = res.bodyBytes;
      if (bytes.length != img.bytes || sha256.convert(bytes).toString() != img.sha256) return false;
      final part = File('${tmp.path}/${img.id}.png');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(imageFile(img.id).path);
      return true;
    } on Exception {
      return false;
    }
  }

  /// 410: the frame was deleted in the app. Wipe the cache and the secret (§9.4).
  Future<void> _removed() async {
    await _wipeCache();
    config
      ..remove('device_secret')
      ..remove('frame_id')
      ..remove('manifest_version')
      ..remove('settings');
    await save();
  }

  Future<void> _wipeCache() async {
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
    await cacheDir.create(recursive: true);
    config
      ..remove('newest_first')
      ..remove('sequential_index')
      ..remove('last_image_id');
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body, {String? bearer}) async {
    final res = await _http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json', if (bearer != null) 'Authorization': 'Bearer $bearer'},
      body: jsonEncode(body),
    );
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException(res.statusCode, 'bad_response', res.body);
    }
    if (res.statusCode >= 300) {
      final err = json['error'] as Map<String, dynamic>? ?? {};
      throw ApiException(res.statusCode, '${err['code'] ?? 'error'}', '${err['message'] ?? res.body}');
    }
    return json;
  }

  static Future<void> _writeAtomic(File f, String content) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }

  static String _hex(int bytes) {
    final r = Random.secure();
    return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void close() => _http.close();
}
