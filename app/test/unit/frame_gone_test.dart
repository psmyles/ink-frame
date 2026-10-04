// A frame whose project was deleted: Supabase answers HTTP 410 for a while, then
// the address stops existing. The frame shows "No longer exists" (not offline or
// signed out), and signing in on a new device skips it. Also: starting offline
// keeps the saved session.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/state/providers.dart';

const frame = FrameAddress('https://gggggggggggggggggggg.supabase.co', 'sb_publishable_gggggggggggg');
const credential = PasswordCredential('alice@dev.test', 'secret1');

/// How the frame's project and Supabase itself answer.
enum Net { deleted, addressGone, asleep, offline, up }

class Server {
  Server(this.net);

  Net net;
  final calls = <String>[];

  late final client = MockClient((req) async {
    calls.add('${req.method} ${req.url.host}${req.url.path}');
    final lookupFailed = SocketException("Failed host lookup: '${req.url.host}'");
    if (req.url.host == 'api.supabase.com') {
      if (net == Net.offline) throw lookupFailed;
      return http.Response('', 404);
    }
    return switch (net) {
      Net.deleted => http.Response('Project removed.', 410),
      Net.addressGone || Net.offline => throw lookupFailed,
      Net.asleep => http.Response('', 540),
      Net.up => http.Response('{}', 200),
    };
  });
}

/// A saved session whose access token expired, so restoring it refreshes.
String expiredSession() {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final exp = DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000;
  return jsonEncode({
    'access_token': '${part({'alg': 'HS256'})}.${part({'sub': 'u1', 'exp': exp})}.sig',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'r1',
    'user': {'id': 'u1', 'aud': 'authenticated', 'app_metadata': {}, 'user_metadata': {}, 'created_at': '2026-09-01T00:00:00Z'},
  });
}

void main() {
  late MemoryStore store;
  late Server server;
  late FramesRepository repo;
  late ProviderContainer container;

  Future<void> setUpWith(Net net, {bool session = true}) async {
    store = MemoryStore();
    server = Server(net);
    repo = FramesRepository(store, connect: (a, s) => FrameConnection(a, s, httpClient: server.client));
    await repo.add(frame);
    if (session) await store.write('session:${frame.ref}', expiredSession());
    container = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store), framesRepositoryProvider.overrideWithValue(repo)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
  }

  Future<String?> viewError() async => (await container.read(frameViewProvider(frame).future)).error?.code;

  group('isGone', () {
    for (final (net, gone) in [
      (Net.deleted, true),
      (Net.addressGone, true),
      (Net.offline, false),
      (Net.asleep, false),
      (Net.up, false),
    ]) {
      test('${net.name}: $gone', () async {
        final s = Server(net);
        expect(await FrameConnection(frame, MemoryStore(), httpClient: s.client).isGone(), gone);
      });
    }

    test('another connection failure is not a missing address', () async {
      final s = MockClient((req) async => req.url.host == 'api.supabase.com'
          ? http.Response('', 404)
          : throw const SocketException('Connection refused'));
      expect(await FrameConnection(frame, MemoryStore(), httpClient: s).isGone(), isFalse);
    });
  });

  test('just deleted (410): the refresh is refused and the frame shows as gone', () async {
    await setUpWith(Net.deleted);
    expect(await viewError(), ApiException.gone);
  });

  test('deleted a while ago (no address, Supabase answers): gone', () async {
    await setUpWith(Net.addressGone, session: false);
    expect(await viewError(), ApiException.gone);
  });

  test('starting offline keeps the saved session and reads the frame once back online', () async {
    await setUpWith(Net.offline);
    expect(await viewError(), ApiException.offline);
    expect(await store.read('session:${frame.ref}'), isNotNull);
    // Not remembered as signed out for the rest of the run: it tries again.
    server
      ..net = Net.up
      ..calls.clear();
    container.invalidate(frameViewProvider(frame));
    await viewError();
    expect(server.calls, contains('POST ${Uri.parse(frame.url).host}/auth/v1/token'));
  }, timeout: const Timeout(Duration(seconds: 40))); // auth retries for ~12 s

  test('signing in to an asleep frame says asleep, not offline', () async {
    await setUpWith(Net.asleep, session: false);
    await expectLater(
      repo.signIn(frame, credential),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiException.asleep)),
    );
  });

  test('signing in on a new device skips a deleted frame instead of failing', () async {
    await setUpWith(Net.deleted, session: false);
    expect(await repo.signInAll([frame], credential), [frame]);
    await expectLater(
      repo.signIn(frame, credential),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiException.gone)),
    );
  });
}
