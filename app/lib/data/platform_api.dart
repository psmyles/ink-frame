import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'backend_bundle.dart';

/// An error from the Supabase Management API, or the app's own codes below.
class PlatformApiException implements Exception {
  const PlatformApiException(this.code, this.message, {this.status});

  final String code;
  final String message;
  final int? status;

  /// The free plan's 2 active projects are used (spike a, the 400's wording).
  static const projectLimit = 'project_limit';

  /// No Supabase account connected on this device.
  static const notConnected = 'not_connected';

  /// The connection was refused (revoked, or the refresh failed): connect again.
  static const reconnect = 'reconnect';

  static const offline = 'offline';

  @override
  String toString() => 'PlatformApiException($code, $status): $message';
}

/// The Supabase Management API (`api.supabase.com`) with the owner's platform token
/// (PLAN.md §5.1, §6.2): only for setting up, updating, waking and deleting frames.
/// `tools/dev/provision.ts` is the reference for these calls.
class PlatformApi {
  PlatformApi(this._token, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final Future<String> Function() _token;
  final http.Client _http;

  static const _base = 'https://api.supabase.com';

  Future<List<({String slug, String name})>> organizations() async => [
        for (final o in await _json('GET', '/v1/organizations') as List)
          (slug: (o as Map<String, dynamic>)['slug'] as String, name: o['name'] as String),
      ];

  /// Creates a project in [region] (`americas`, `emea` or `apac`); returns its ref.
  Future<String> createProject({required String name, required String org, required String dbPass, required String region}) async {
    final r = await _json('POST', '/v1/projects', body: {
      'name': name,
      'organization_slug': org,
      'db_pass': dbPass,
      'region_selection': {'type': 'smartGroup', 'code': region},
    });
    return (r as Map<String, dynamic>)['ref'] as String;
  }

  Future<String> status(String ref) async => ((await _json('GET', '/v1/projects/$ref')) as Map<String, dynamic>)['status'] as String;

  /// Whether the services a frame needs are up.
  Future<bool> healthy(String ref) async {
    final r = await _json('GET', '/v1/projects/$ref/health?services=db,auth,rest,storage') as List;
    return r.isNotEmpty && r.every((h) => (h as Map<String, dynamic>)['healthy'] == true);
  }

  /// Runs SQL as postgres (several statements allowed).
  Future<List<Map<String, dynamic>>> sql(String ref, String query) async =>
      [for (final row in await _json('POST', '/v1/projects/$ref/database/query', body: {'query': query}) as List) row as Map<String, dynamic>];

  /// Deploys an Edge Function from its sources (bundled by Supabase).
  Future<void> deployFunction(String ref, String slug, List<SourceFile> files) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/v1/projects/$ref/functions/deploy?slug=$slug'))
      ..fields['metadata'] = jsonEncode({'entrypoint_path': '$slug/index.ts', 'name': slug, 'verify_jwt': false})
      ..files.addAll([
        for (final f in files) http.MultipartFile.fromString('file', f.contents, filename: f.path, contentType: MediaType('application', 'typescript')),
      ]);
    await _send(req);
  }

  Future<void> configureAuth(String ref, Map<String, Object?> config) => _json('PATCH', '/v1/projects/$ref/config/auth', body: config);

  /// The project's publishable key (returned without revealing the secret ones).
  Future<String> publishableKey(String ref) async {
    for (final k in await _json('GET', '/v1/projects/$ref/api-keys') as List) {
      final key = k as Map<String, dynamic>;
      if (key['type'] == 'publishable' && key['api_key'] is String) return key['api_key'] as String;
    }
    throw const PlatformApiException('no_key', 'The project has no publishable key.');
  }

  /// Wakes a paused project (~3 min until healthy, spike a).
  Future<void> restore(String ref) => _json('POST', '/v1/projects/$ref/restore', body: const <String, Object>{});

  Future<void> deleteProject(String ref) => _json('DELETE', '/v1/projects/$ref');

  Future<Object?> _json(String method, String path, {Object? body}) async {
    final req = http.Request(method, Uri.parse('$_base$path'));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final text = await _send(req);
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<String> _send(http.BaseRequest req) async {
    req.headers['Authorization'] = 'Bearer ${await _token()}';
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 60)));
    } on SocketException catch (e) {
      throw PlatformApiException(PlatformApiException.offline, e.message);
    } on http.ClientException catch (e) {
      throw PlatformApiException(PlatformApiException.offline, e.message);
    } on TimeoutException {
      throw const PlatformApiException(PlatformApiException.offline, 'Timed out.');
    }
    if (res.statusCode < 400) return res.body;
    final text = res.body;
    if (res.statusCode == 401) throw PlatformApiException(PlatformApiException.reconnect, text, status: 401);
    if (res.statusCode == 400 && (text.contains('project limit') || text.contains('maximum limits'))) {
      throw PlatformApiException(PlatformApiException.projectLimit, text, status: 400);
    }
    throw PlatformApiException('http_${res.statusCode}', '${req.method} ${req.url.path} → ${res.statusCode}: $text', status: res.statusCode);
  }
}
