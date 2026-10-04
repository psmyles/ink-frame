import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/api_error.dart';
import '../data/frame_api.dart';
import '../data/frame_link.dart';
import '../data/models.dart';
import '../data/secure_store.dart';

/// A frame whose battery is below its warning level, to notify about once.
class LowBattery {
  const LowBattery(this.address, this.name, this.batteryPct);

  final FrameAddress address;
  final String name;
  final int batteryPct;
}

/// The low-battery notification (PLAN.md §15): each person chooses on each phone
/// ("Notify me when it's low"; on by default for the owner). A background check reads
/// every watched frame with this device's read-only watch token (`GET /app-api/watch`),
/// never with the sign-in session, whose refresh tokens rotate.
///
/// Kept under `battery_watch` in a store the background check can read while the
/// phone is locked.
class BatteryWatch {
  BatteryWatch(this._store, {http.Client? httpClient, this.supported = true}) : _http = httpClient ?? http.Client();

  final KeyValueStore _store;
  final http.Client _http;

  /// Phones only: desktops have no background checks.
  final bool supported;

  static const _key = 'battery_watch';

  /// Frames already brought in line with their choice in this run.
  final _synced = <String>{};

  // Every change runs after the previous one, so saves don't overwrite each other.
  Future<void> _last = Future.value();

  Future<T> _serial<T>(Future<T> Function() body) {
    final result = _last.then((_) => body());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, _Entry>> _load() async {
    final raw = await _store.read(_key);
    if (raw == null) return {};
    return {
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries) e.key: _Entry.fromJson(e.value as Map<String, dynamic>),
    };
  }

  Future<void> _save(Map<String, _Entry> all) =>
      _store.write(_key, jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}));

  /// What this phone does for [a]: null when nobody chose (then: on for the owner).
  Future<bool?> choice(FrameAddress a) async => supported ? (await _load())[a.url]?.on : null;

  /// Whether the frame's backend has watch tokens (false until the owner updates it).
  Future<bool> available(FrameAddress a) async => supported && !((await _load())[a.url]?.unsupported ?? false);

  static bool wanted(bool? choice, {required bool isOwner}) => choice ?? isOwner;

  /// Once per run, after the frame was read: gets or drops this phone's token to
  /// match the choice.
  Future<void> sync(FrameAddress a, FrameSummary s, FrameApi api) async {
    if (!supported || !_synced.add(a.url)) return;
    await _serial(() async {
      final e = (await _load())[a.url];
      await _apply(a, wanted(e?.on, isOwner: s.isMine), api);
    });
  }

  /// "Notify me when it's low" turned on or off on this phone.
  Future<void> choose(FrameAddress a, bool on, FrameApi api) => _serial(() async {
        final all = await _load();
        all[a.url] = (all[a.url] ?? _Entry(a)).copyWith(on: on, unsupported: false);
        await _save(all);
        await _apply(a, on, api);
      });

  Future<void> _apply(FrameAddress a, bool on, FrameApi api) async {
    final all = await _load();
    final e = all[a.url] ?? _Entry(a);
    if (on && e.token == null) {
      try {
        all[a.url] = e.copyWith(token: await api.createWatchToken(), unsupported: false);
      } on ApiException catch (err) {
        // An older backend: no watch tokens until the owner updates the frame.
        if (err.code != 'not_found') return;
        all[a.url] = e.copyWith(unsupported: true);
      }
      await _save(all);
    } else if (!on && e.token != null) {
      await _revoke(a, e.token!);
      all[a.url] = e.copyWith(token: null);
      await _save(all);
    }
  }

  /// The owner updated [a]'s backend: try watch tokens again at the next read.
  Future<void> updated(FrameAddress a) => _serial(() async {
        if (!supported) return;
        final all = await _load();
        final e = all[a.url];
        _synced.remove(a.url);
        if (e == null || !e.unsupported) return;
        all[a.url] = e.copyWith(unsupported: false);
        await _save(all);
      });

  /// Signed out of, removed from or left [a]: this phone stops checking it.
  Future<void> forget(FrameAddress a) => _serial(() async {
        if (!supported) return;
        final all = await _load();
        final e = all.remove(a.url);
        _synced.remove(a.url);
        if (e == null) return;
        await _save(all);
        if (e.token != null) await _revoke(a, e.token!);
      });

  Future<void> forgetAll() => _serial(() async {
        if (!supported) return;
        final all = await _load();
        await _store.delete(_key);
        _synced.clear();
        for (final e in all.values) {
          if (e.token != null) await _revoke(e.address, e.token!);
        }
      });

  /// The background check: each watched frame's battery. Returns the frames that
  /// just went below their level (each once, until it's charged above it again).
  Future<List<LowBattery>> check() => _serial(() async {
        final all = await _load();
        final low = <LowBattery>[];
        for (final entry in all.entries.toList()) {
          final e = entry.value;
          final token = e.token;
          if (token == null) continue;
          final Map<String, dynamic> w;
          try {
            w = await _watch(e.address, token);
          } on ApiException catch (err) {
            // Left the frame, deleted the account or the frame was deleted: nothing
            // more to check.
            if (err.code == 'invalid_watch_token' || err.code == ApiException.gone) all.remove(entry.key);
            continue;
          }
          final battery = w['battery_pct'] as int?;
          final level = w['low_battery_pct'] as int?;
          final isLow = battery != null && level != null && (w['connected'] as bool? ?? true) && battery < level;
          if (isLow && !e.notified) low.add(LowBattery(e.address, w['name'] as String, battery));
          all[entry.key] = e.copyWith(notified: isLow);
        }
        await _save(all);
        return low;
      });

  Uri _url(FrameAddress a) => Uri.parse('${a.url}/functions/v1/app-api/watch');

  Future<Map<String, dynamic>> _watch(FrameAddress a, String token) async {
    try {
      final res = await _http.get(_url(a), headers: {'x-watch-token': token}).timeout(const Duration(seconds: 30));
      // A deleted project answers 410 in plain text.
      if (res.statusCode == 410) throw ApiException.fromResponse(410, null);
      final body = res.body.isEmpty ? null : jsonDecode(res.body);
      if (res.statusCode >= 400) throw ApiException.fromResponse(res.statusCode, body);
      return body as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw ApiException(ApiException.offline, e.message);
    } on http.ClientException catch (e) {
      throw ApiException(ApiException.offline, e.message);
    } on TimeoutException {
      throw const ApiException(ApiException.offline, 'Timed out.');
    } on FormatException catch (e) {
      throw ApiException('bad_response', e.message);
    }
  }

  Future<void> _revoke(FrameAddress a, String token) async {
    try {
      await _http.delete(_url(a), headers: {'x-watch-token': token}).timeout(const Duration(seconds: 15));
    } catch (_) {
      // Best effort: an unused token does nothing.
    }
  }
}

class _Entry {
  const _Entry(this.address, {this.on, this.token, this.notified = false, this.unsupported = false});

  final FrameAddress address;
  final bool? on;
  final String? token;

  /// Already notified for the current low spell.
  final bool notified;
  final bool unsupported;

  static const _keep = Object();

  _Entry copyWith({Object? on = _keep, Object? token = _keep, bool? notified, bool? unsupported}) => _Entry(
        address,
        on: on == _keep ? this.on : on as bool?,
        token: token == _keep ? this.token : token as String?,
        notified: notified ?? this.notified,
        unsupported: unsupported ?? this.unsupported,
      );

  Map<String, Object?> toJson() =>
      {...address.toJson(), 'on': on, 'token': token, 'notified': notified, 'unsupported': unsupported};

  factory _Entry.fromJson(Map<String, dynamic> j) => _Entry(
        FrameAddress.fromJson(j),
        on: j['on'] as bool?,
        token: j['token'] as String?,
        notified: j['notified'] as bool? ?? false,
        unsupported: j['unsupported'] as bool? ?? false,
      );
}
