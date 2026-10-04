import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_error.dart';
import 'frame_connection.dart';
import 'frame_link.dart';
import 'secure_store.dart';

/// The directory (`shared/api/directory.yaml`): which frames each Google or Apple
/// account is on, so signing in on a new device finds them without a link
/// (app-flow §1.4).
///
/// Keeps its device token and the changes not sent yet under `directory`. Changes
/// go out at once, or at the next [flush] (app start). Apart from [signIn], nothing
/// here throws: a join or leave never fails because of the directory.
class FrameDirectory {
  FrameDirectory(this._store, {http.Client? httpClient, String baseUrl = AppConfig.directoryUrl})
      : _http = httpClient ?? http.Client(),
        _base = baseUrl;

  final KeyValueStore _store;
  final http.Client _http;
  final String _base;

  bool get available => _base.isNotEmpty;

  // Every call runs after the previous one, so their saves don't overwrite each other.
  Future<void> _last = Future.value();

  Future<T> _serial<T>(Future<T> Function() body) {
    final result = _last.then((_) => body());
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Signs in with a Google/Apple ID token and returns the account's frames. Throws
  /// [ApiException] (`offline`, `invalid_id_token`, …).
  Future<List<FrameAddress>> signIn(IdTokenCredential credential) => _serial(() => _signIn(credential));

  Future<List<FrameAddress>> _signIn(IdTokenCredential credential) async {
    final r = await _call('POST', '/sign-in', body: {'id_token': credential.idToken}) as Map<String, dynamic>;
    await _save((await _load()).withToken(r['token'] as String, provider: credential.provider.name));
    return await _flush() ?? _frames(r);
  }

  static List<FrameAddress> _frames(Object? response) =>
      [for (final f in (response as Map<String, dynamic>)['frames'] as List) FrameAddress.fromJson(f as Map<String, dynamic>)];

  /// The account's frames, to find ones added on another device (app-flow §1.4).
  /// Null without a device token or when the directory can't be reached.
  Future<List<FrameAddress>?> list() => _serial(() async {
        if (!available) return null;
        final changed = await _flush();
        if (changed != null) return changed;
        final s = await _load();
        if (s.token == null) return null;
        try {
          return _frames(await _call('GET', '/frames', token: s.token));
        } on ApiException catch (e) {
          if (e.code == 'invalid_token') await _save((await _load()).withToken(null));
          return null;
        }
      });

  /// How this device signed in to the directory: `google` or `apple` (null if unknown).
  Future<String?> provider() => _serial(() async => (await _load()).provider);

  /// Puts frames on the account's list after joining or signing in to them with
  /// [signedInWith]; that sign-in also gets this device a token if it has none.
  Future<void> add(List<FrameAddress> frames, {Credential? signedInWith}) => _serial(() async {
        if (!available || frames.isEmpty) return;
        final s = await _load();
        if (s.token == null && signedInWith is! IdTokenCredential) return; // dev-mode email: not in the directory
        await _save(s.adding(frames));
        if (s.token != null) {
          await _flush();
          return;
        }
        try {
          await _signIn(signedInWith as IdTokenCredential);
        } on ApiException {
          // Sent after the next sign-in.
        }
      });

  /// Takes frames off the list (left the frame, or no longer on it).
  Future<void> remove(List<FrameAddress> frames) => _serial(() async {
        if (!available || frames.isEmpty) return;
        final s = await _load();
        if (s.token == null) return;
        await _save(s.removing(frames));
        await _flush();
      });

  /// Sends the changes not sent yet.
  Future<void> flush() => _serial(_flush);

  /// The list after the change, if there was one to send and it went out.
  Future<List<FrameAddress>?> _flush() async {
    final sent = await _load();
    if (!available || sent.token == null || sent.isEmpty) return null;
    try {
      final r = await _call('POST', '/frames', token: sent.token, body: {
        'add': [for (final f in sent.add) f.toJson()],
        'remove': sent.remove,
      });
      await _save((await _load()).without(sent));
      return _frames(r);
    } on ApiException catch (e) {
      switch (e.code) {
        case ApiException.offline || 'internal' || 'http_502' || 'http_503':
          break; // next time
        case 'invalid_token':
          await _save((await _load()).withToken(null)); // kept for the next sign-in
        default:
          await _save((await _load()).without(sent)); // would never succeed
      }
      return null;
    }
  }

  /// Sign out: this device stops being able to change the list.
  Future<void> signOut() => _serial(() async {
        final token = (await _load()).token;
        await _store.delete(_key);
        if (available && token != null) await _quietly(() => _call('POST', '/sign-out', token: token));
      });

  /// Delete my account: the directory forgets the account entirely.
  Future<void> forget() => _serial(() async {
        final token = (await _load()).token;
        await _store.delete(_key);
        if (available && token != null) await _quietly(() => _call('DELETE', '/me', token: token));
      });

  static const _key = 'directory';

  Future<_State> _load() async {
    final raw = await _store.read(_key);
    return raw == null ? const _State() : _State.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(_State s) => _store.write(_key, jsonEncode(s.toJson()));

  static Future<void> _quietly(Future<Object?> Function() call) async {
    try {
      await call();
    } on ApiException {
      // Best effort.
    }
  }

  Future<Object?> _call(String method, String path, {String? token, Object? body}) async {
    final req = http.Request(method, Uri.parse('$_base/v1$path'))
      ..headers.addAll({
        if (token != null) 'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) req.body = jsonEncode(body);
    try {
      final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 15)));
      Object? decoded;
      try {
        decoded = res.body.isEmpty ? null : jsonDecode(res.body);
      } on FormatException {
        decoded = null;
      }
      if (res.statusCode >= 400) throw ApiException.fromResponse(res.statusCode, decoded);
      return decoded;
    } on SocketException catch (e) {
      throw ApiException(ApiException.offline, e.message);
    } on http.ClientException catch (e) {
      throw ApiException(ApiException.offline, e.message);
    } on TimeoutException {
      throw const ApiException(ApiException.offline, 'Timed out.');
    }
  }
}

/// The device token and the changes not sent yet.
class _State {
  const _State({this.token, this.provider, this.add = const [], this.remove = const []});

  final String? token;

  /// `google` or `apple`: which sign-in finds this account's frames.
  final String? provider;
  final List<FrameAddress> add;
  final List<String> remove;

  bool get isEmpty => add.isEmpty && remove.isEmpty;

  _State withToken(String? t, {String? provider}) =>
      _State(token: t, provider: provider ?? this.provider, add: add, remove: remove);

  _State adding(List<FrameAddress> frames) {
    final urls = {for (final f in frames) f.url};
    return _State(
      token: token,
      provider: provider,
      add: [for (final f in add) if (!urls.contains(f.url)) f, ...frames],
      remove: [for (final u in remove) if (!urls.contains(u)) u],
    );
  }

  _State removing(List<FrameAddress> frames) {
    final urls = {for (final f in frames) f.url};
    return _State(
      token: token,
      provider: provider,
      add: [for (final f in add) if (!urls.contains(f.url)) f],
      remove: [...remove.where((u) => !urls.contains(u)), ...urls],
    );
  }

  /// What's left after [sent] went out (changes made meanwhile stay).
  _State without(_State sent) => _State(
        token: token,
        provider: provider,
        add: [for (final f in add) if (!sent.add.contains(f)) f],
        remove: [for (final u in remove) if (!sent.remove.contains(u)) u],
      );

  Map<String, Object?> toJson() => {
        'token': token,
        'provider': provider,
        'add': [for (final f in add) f.toJson()],
        'remove': remove,
      };

  factory _State.fromJson(Map<String, dynamic> j) => _State(
        token: j['token'] as String?,
        provider: j['provider'] as String?,
        add: [for (final f in j['add'] as List? ?? const []) FrameAddress.fromJson(f as Map<String, dynamic>)],
        remove: [for (final u in j['remove'] as List? ?? const []) u as String],
      );
}
