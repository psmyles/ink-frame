import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'platform_api.dart' as api;
import 'secure_store.dart';

/// Thrown when the person closes the Supabase consent page; the screen stays put.
class ConnectCancelled implements Exception {
  const ConnectCancelled();
}

/// Opens [url] in the system browser and returns the URL it redirected to.
typedef OAuthBrowser = Future<Uri> Function(Uri url, String callbackScheme);

Future<Uri> _systemBrowser(Uri url, String callbackScheme) async {
  try {
    return Uri.parse(await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: callbackScheme,
      options: const FlutterWebAuth2Options(useWebview: false),
    ));
  } on PlatformException catch (e) {
    if (e.code == 'CANCELED') throw const ConnectCancelled();
    rethrow;
  }
}

/// The owner's Supabase account on this device (PLAN.md §5.1): an OAuth token from
/// "Connect Supabase", or a personal access token in developer mode. Kept in secure
/// storage under `supabase_platform`, on this device only.
///
/// Supabase needs the OAuth App's secret to exchange the code and refresh tokens
/// (spike c), so both go through the directory Worker, which adds it. PKCE keeps the
/// code useless to anyone without the verifier.
class PlatformAuth {
  PlatformAuth(
    this._store, {
    http.Client? httpClient,
    String directoryUrl = AppConfig.directoryUrl,
    OAuthBrowser? browser,
    DateTime Function()? now,
    bool? desktopLoopback,
  })  : _http = httpClient ?? http.Client(),
        _directory = directoryUrl,
        _browser = browser ?? _systemBrowser,
        _now = now ?? DateTime.now,
        _loopback = desktopLoopback ?? (Platform.isWindows || Platform.isLinux);

  final KeyValueStore _store;
  final http.Client _http;
  final String _directory;
  final OAuthBrowser _browser;
  final DateTime Function() _now;

  /// Windows/Linux catch the redirect on localhost; phones and Macs go through the
  /// HTTPS bounce page (central/site/oauth) back to inkframe://supabase-oauth.
  final bool _loopback;

  static const _key = 'supabase_platform';
  static const loopbackRedirect = 'http://localhost:53682/callback';
  static const bounceRedirect = '${AppConfig.pagesUrl}/oauth/';

  Future<Map<String, dynamic>?> _load() async {
    final raw = await _store.read(_key);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _save(Map<String, Object?> v) => _store.write(_key, jsonEncode(v));

  Future<bool> get isConnected async => await _load() != null;

  /// Connected with a personal access token (developer mode).
  Future<bool> get isPersonalToken async => (await _load())?['pat'] != null;

  /// "Connect Supabase": consent in the browser, then the code exchange.
  Future<void> connect() async {
    final redirect = _loopback ? loopbackRedirect : bounceRedirect;
    final verifier = _random(48);
    final state = _random(16);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final url = Uri.https('api.supabase.com', '/v1/oauth/authorize', {
      'client_id': AppConfig.supabaseOAuthClientId,
      'response_type': 'code',
      'redirect_uri': redirect,
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });
    final back = await _browser(url, _loopback ? 'http://localhost:53682' : 'inkframe');
    final q = back.queryParameters;
    if (q['error'] != null) {
      if (q['error'] == 'access_denied') throw const ConnectCancelled();
      throw api.PlatformApiException('oauth_failed', q['error_description'] ?? q['error']!);
    }
    if (q['state'] != state || q['code'] == null) throw const api.PlatformApiException('oauth_failed', 'The answer from Supabase was not for this request.');
    await _saveTokens(await _token({
      'grant_type': 'authorization_code',
      'code': q['code']!,
      'code_verifier': verifier,
      'redirect_uri': redirect,
    }));
  }

  /// Developer mode: a personal access token instead of OAuth.
  Future<void> usePersonalToken(String pat) => _save({'pat': pat.trim()});

  Future<void> disconnect() => _store.delete(_key);

  /// A token for the Management API, refreshed when it's about to expire. Throws
  /// [api.PlatformApiException] `not_connected` or `reconnect`.
  Future<String> accessToken() async {
    final s = await _load();
    if (s == null) throw const api.PlatformApiException(api.PlatformApiException.notConnected, 'Connect Supabase first.');
    if (s['pat'] case final String pat) return pat;
    final expires = DateTime.fromMillisecondsSinceEpoch(s['expires_at'] as int);
    if (_now().isBefore(expires.subtract(const Duration(minutes: 5)))) return s['access_token'] as String;
    try {
      return await _saveTokens(await _token({'grant_type': 'refresh_token', 'refresh_token': s['refresh_token'] as String}));
    } on api.PlatformApiException catch (e) {
      if (e.code == 'oauth_failed') {
        await disconnect();
        throw api.PlatformApiException(api.PlatformApiException.reconnect, e.message);
      }
      rethrow;
    }
  }

  Future<String> _saveTokens(Map<String, dynamic> t) async {
    final access = t['access_token'] as String;
    await _save({
      'access_token': access,
      'refresh_token': t['refresh_token'],
      'expires_at': _now().add(Duration(seconds: (t['expires_in'] as num).toInt())).millisecondsSinceEpoch,
    });
    return access;
  }

  /// `POST /v1/supabase-oauth/token` on the directory Worker (shared/api/directory.yaml).
  Future<Map<String, dynamic>> _token(Map<String, String> body) async {
    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse('$_directory/v1/supabase-oauth/token'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw api.PlatformApiException(api.PlatformApiException.offline, e.message);
    } on http.ClientException catch (e) {
      throw api.PlatformApiException(api.PlatformApiException.offline, e.message);
    } on TimeoutException {
      throw const api.PlatformApiException(api.PlatformApiException.offline, 'Timed out.');
    }
    Map<String, dynamic>? j;
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>;
    } on FormatException {
      j = null;
    }
    if (res.statusCode == 200 && j?['access_token'] is String) return j!;
    final error = j?['error'] as Map<String, dynamic>?;
    throw api.PlatformApiException(
      res.statusCode == 401 ? 'oauth_failed' : (error?['code'] as String? ?? 'http_${res.statusCode}'),
      error?['message'] as String? ?? 'Token exchange failed (${res.statusCode}).',
      status: res.statusCode,
    );
  }

  static String _random(int bytes) {
    final r = Random.secure();
    return base64Url.encode(List.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
  }
}
