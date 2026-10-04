import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_frame/data/backend_bundle.dart';
import 'package:ink_frame/data/platform_api.dart';
import 'package:ink_frame/data/provisioner.dart';

/// One project in [FakePlatform].
class FakeProject {
  FakeProject(this.ref, this.name);

  final String ref;
  final String name;
  var status = 'COMING_UP';
  var polls = 0;
  var schemaVersion = 0;
  final config = <String, String>{};
  final deployed = <String>[];
  Map<String, Object?>? auth;
  String? frameName;
  String? owner;
}

/// The Management API in memory, understanding the calls and SQL the Provisioner
/// makes (tools/dev/provision.ts is the reference). A new project is healthy after
/// [pollsUntilReady] status checks.
class FakePlatform {
  FakePlatform({this.pollsUntilReady = 2, this.projectLimit = 2});

  final int pollsUntilReady;
  final int projectLimit;
  final projects = <String, FakeProject>{};
  final calls = <String>[];

  /// Makes the next call fail with this status (then clears).
  int? failNext;
  var _n = 0;

  late final client = MockClient((req) async {
    final path = req.url.path;
    calls.add('${req.method} $path');
    if (failNext case final status?) {
      failNext = null;
      return http.Response('{"message":"failed"}', status);
    }
    http.Response json(Object? body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});
    final m = RegExp(r'^/v1/projects/([a-z0-9]+)(/.*)?$').firstMatch(path);
    final p = m == null ? null : projects[m.group(1)];
    final sub = m?.group(2) ?? '';

    switch ((req.method, path)) {
      case ('GET', '/v1/organizations'):
        return json([
          {'slug': 'org-1', 'name': "Priya's Org"},
        ]);
      case ('POST', '/v1/projects'):
        if (projects.length >= projectLimit) {
          return json({'message': 'The following organization members have reached their maximum limits ... (2 project limit).'}, 400);
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final ref = 'proj${(_n++).toString().padLeft(16, '0')}';
        projects[ref] = FakeProject(ref, body['name'] as String);
        return json({'ref': ref, 'status': 'COMING_UP'}, 201);
    }
    if (p == null) return json({'message': 'not found'}, 404);
    switch ((req.method, sub)) {
      case ('GET', ''):
        // Starting or waking up: healthy after a few checks. Paused stays paused.
        if ((p.status == 'COMING_UP' || p.status == 'RESTORING') && ++p.polls >= pollsUntilReady) p.status = 'ACTIVE_HEALTHY';
        return json({'ref': p.ref, 'status': p.status});
      case ('GET', '/health'):
        return json([
          for (final s in ['db', 'auth', 'rest', 'storage']) {'name': s, 'healthy': p.status == 'ACTIVE_HEALTHY'},
        ]);
      case ('POST', '/database/query'):
        return json(_sql(p, (jsonDecode(req.body) as Map<String, dynamic>)['query'] as String));
      case ('POST', '/functions/deploy'):
        p.deployed.add(req.url.queryParameters['slug']!);
        return json({'version': p.deployed.length});
      case ('PATCH', '/config/auth'):
        p.auth = jsonDecode(req.body) as Map<String, dynamic>;
        return json({});
      case ('GET', '/api-keys'):
        return json([
          {'type': 'publishable', 'name': 'default', 'api_key': 'sb_publishable_${p.ref}'},
          {'type': 'secret', 'name': 'default', 'api_key': 'sb_secret_••••'},
        ]);
      case ('POST', '/restore'):
        p.status = 'RESTORING';
        p.polls = 0;
        return json({});
      case ('DELETE', ''):
        projects.remove(p.ref);
        return json({'ref': p.ref});
    }
    return json({'message': 'unknown ${req.method} $path'}, 404);
  });

  List<Map<String, Object?>> _sql(FakeProject p, String q) {
    String lit(String s) => s.replaceAll("''", "'");
    if (q.contains("to_regclass('public.schema_version')")) return [{'exists': p.schemaVersion > 0}];
    if (q.contains('max(version)')) return [{'v': p.schemaVersion}];
    if (RegExp(r'insert into public\.schema_version \(version\) values \((\d+)\)').firstMatch(q) case final m?) {
      p.schemaVersion = int.parse(m.group(1)!);
      return [];
    }
    if (RegExp(r"insert into private\.config \(key, value\) values \('(\w+)', '((?:[^']|'')*)'\)").firstMatch(q) case final m?) {
      p.config[m.group(1)!] = lit(m.group(2)!);
      return [];
    }
    if (q.contains("from private.config where key = 'backend'")) {
      return [if (p.config['backend'] case final v?) {'value': v}];
    }
    if (q.contains('count(*)::int as n from public.frame')) return [{'n': p.frameName == null ? 0 : 1}];
    if (RegExp(r"private\.setup_frame\('((?:[^']|'')*)'").firstMatch(q) case final m?) {
      p.frameName = lit(m.group(1)!);
      return [];
    }
    if (q.contains("from public.members where role = 'owner'")) return [if (p.owner != null) {'user_id': p.owner}];
    if (RegExp(r"private\.set_owner\('([0-9a-f-]+)'").firstMatch(q) case final m?) {
      p.owner = m.group(1);
      return [];
    }
    return []; // the seed
  }

  PlatformApi api() => PlatformApi(() async => 'token', httpClient: client);

  Provisioner provisioner([BackendBundle? bundle]) =>
      Provisioner(api(), bundle ?? testBundle, pollEvery: Duration.zero, sleep: (_) async {});
}

const testBundle = BackendBundle(
  migrations: [Migration(1, '-- 1'), Migration(2, '-- 2')],
  seed: '-- seed',
  functions: {
    'device-api': [SourceFile('device-api/index.ts', '// d'), SourceFile('_shared/db.ts', '// s')],
    'app-api': [SourceFile('app-api/index.ts', '// a'), SourceFile('_shared/db.ts', '// s')],
  },
  models: [
    ModelOption(id: 'reterminal-e1002', name: 'reTerminal E1002 7.3"', width: 800, height: 480),
    ModelOption(id: 'other-7-3', name: 'Test panel 7.3"', width: 800, height: 480),
  ],
  auth: {'external_google_enabled': true},
  fingerprint: 'fp-2',
);
