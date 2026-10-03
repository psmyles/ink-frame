// "Connect Supabase" (PLAN.md §5.1, spike c): consent in the browser with PKCE, the
// code exchanged and tokens refreshed through the directory Worker (which holds the
// client secret), a personal access token in developer mode.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_frame/config/app_config.dart';
import 'package:ink_frame/data/platform_api.dart';
import 'package:ink_frame/data/platform_auth.dart';
import 'package:ink_frame/data/secure_store.dart';

/// The Worker's `/v1/supabase-oauth/token`: checks PKCE like Supabase would.
class FakeWorker {
  final requests = <Map<String, dynamic>>[];
  String? challenge;
  var refreshOk = true;
  var n = 0;

  late final client = MockClient((req) async {
    expect(req.url.path, '/v1/supabase-oauth/token');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    requests.add(body);
    final ok = switch (body['grant_type']) {
      'authorization_code' => body['code'] == 'the-code' &&
          base64Url.encode(sha256.convert(ascii.encode(body['code_verifier'] as String)).bytes).replaceAll('=', '') == challenge,
      'refresh_token' => refreshOk && body['refresh_token'] == 'refresh-$n',
      _ => false,
    };
    if (!ok) return http.Response(jsonEncode({'error': {'code': 'oauth_failed', 'message': 'nope'}}), 401);
    n++;
    return http.Response(jsonEncode({'access_token': 'access-$n', 'refresh_token': 'refresh-$n', 'expires_in': 86400}), 200);
  });
}

void main() {
  late MemoryStore store;
  late FakeWorker worker;
  late DateTime now;
  Uri? opened;

  PlatformAuth auth({bool loopback = false, String Function(Uri url)? answer}) => PlatformAuth(
        store,
        httpClient: worker.client,
        directoryUrl: 'https://dir.test',
        now: () => now,
        desktopLoopback: loopback,
        browser: (url, scheme) async {
          opened = url;
          worker.challenge = url.queryParameters['code_challenge'];
          final redirect = url.queryParameters['redirect_uri']!;
          return Uri.parse(answer?.call(url) ??
              '${scheme == 'inkframe' ? 'inkframe://supabase-oauth' : redirect}?code=the-code&state=${url.queryParameters['state']}');
        },
      );

  setUp(() {
    store = MemoryStore();
    worker = FakeWorker();
    now = DateTime(2026, 10, 3, 12);
    opened = null;
  });

  test('connect: consent with PKCE, the code goes through the Worker, no secret', () async {
    final a = auth();
    expect(await a.isConnected, isFalse);
    await a.connect();
    expect(opened!.host, 'api.supabase.com');
    expect(opened!.queryParameters['client_id'], AppConfig.supabaseOAuthClientId);
    expect(opened!.queryParameters['code_challenge_method'], 'S256');
    expect(opened!.queryParameters['redirect_uri'], 'https://psmyles.github.io/ink-frame/oauth/');
    expect(worker.requests.single['redirect_uri'], 'https://psmyles.github.io/ink-frame/oauth/');
    expect(worker.requests.single.keys, isNot(contains('client_secret')));
    expect(await a.isConnected, isTrue);
    expect(await a.accessToken(), 'access-1');
  });

  test('Windows and Linux come back on localhost', () async {
    await auth(loopback: true).connect();
    expect(opened!.queryParameters['redirect_uri'], 'http://localhost:53682/callback');
  });

  test('the token is refreshed shortly before it expires', () async {
    final a = auth();
    await a.connect();
    now = now.add(const Duration(hours: 23, minutes: 50));
    expect(await a.accessToken(), 'access-1');
    now = now.add(const Duration(minutes: 6));
    expect(await a.accessToken(), 'access-2');
    expect(worker.requests.last, {'grant_type': 'refresh_token', 'refresh_token': 'refresh-1'});
  });

  test('a refused refresh disconnects and asks to connect again', () async {
    final a = auth();
    await a.connect();
    worker.refreshOk = false;
    now = now.add(const Duration(days: 2));
    await expectLater(a.accessToken(), throwsA(isA<PlatformApiException>().having((e) => e.code, 'code', PlatformApiException.reconnect)));
    expect(await a.isConnected, isFalse);
  });

  test('declined, or an answer for another request', () async {
    await expectLater(auth(answer: (_) => 'inkframe://supabase-oauth?error=access_denied').connect(), throwsA(isA<ConnectCancelled>()));
    await expectLater(
      auth(answer: (_) => 'inkframe://supabase-oauth?code=the-code&state=someone-elses').connect(),
      throwsA(isA<PlatformApiException>()),
    );
    expect(await auth().isConnected, isFalse);
  });

  test('developer mode: a personal access token', () async {
    final a = auth();
    await expectLater(a.accessToken(), throwsA(isA<PlatformApiException>().having((e) => e.code, 'code', PlatformApiException.notConnected)));
    await a.usePersonalToken(' sbp_dev ');
    expect(await a.accessToken(), 'sbp_dev');
    expect(await a.isPersonalToken, isTrue);
    await a.disconnect();
    expect(await a.isConnected, isFalse);
  });
}
