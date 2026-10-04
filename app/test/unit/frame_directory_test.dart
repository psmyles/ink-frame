// The app's side of the directory (app-flow §1.4): the device token, queued
// changes, and that nothing here gets in the way of joining or leaving.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_directory.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import 'fake_directory.dart';

const kitchen = FrameAddress('https://aaaaaaaaaaaaaaaaaaaa.supabase.co', 'sb_publishable_aaaaaaaaaaaa');
const hallway = FrameAddress('https://bbbbbbbbbbbbbbbbbbbb.supabase.co', 'sb_publishable_bbbbbbbbbbbb');

IdTokenCredential google(String account) => IdTokenCredential(provider: OAuthProvider.google, idToken: account);

void main() {
  late FakeDirectoryServer server;
  late MemoryStore store;
  late FrameDirectory directory;

  setUp(() {
    server = FakeDirectoryServer();
    store = MemoryStore();
    directory = server.directory(store);
  });

  Future<String?> savedToken() async {
    final raw = await store.read('directory');
    return raw == null ? null : (jsonDecode(raw) as Map<String, dynamic>)['token'] as String?;
  }

  test('signing in returns the account\'s frames and keeps a device token', () async {
    server.accounts['alice'] = [kitchen, hallway];
    expect(await directory.signIn(google('alice')), [kitchen, hallway]);
    expect(await savedToken(), 'tok0');
  });

  test('list: the account\'s frames (with ones added elsewhere); null without a token or connection', () async {
    expect(await directory.list(), isNull);
    expect(server.calls, isEmpty);

    server.accounts['alice'] = [kitchen];
    await directory.signIn(google('alice'));
    server.accounts['alice']!.add(hallway); // joined on another device
    expect(await directory.list(), [kitchen, hallway]);
    expect(server.calls.last, 'GET /frames');
    expect(await directory.provider(), 'google');

    server.offline = true;
    expect(await directory.list(), isNull);
  });

  test('a bad ID token is an error', () async {
    await expectLater(
      directory.signIn(google('bad')),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_id_token')),
    );
  });

  test('joining puts the frame on the list; the first time also gets a token', () async {
    await directory.add([kitchen], signedInWith: google('alice'));
    expect(server.calls, ['POST /sign-in', 'POST /frames']);
    expect(server.accounts['alice'], [kitchen]);

    // Later changes use the token; no new sign-in.
    await directory.add([hallway], signedInWith: google('alice'));
    await directory.remove([kitchen]);
    expect(server.calls, ['POST /sign-in', 'POST /frames', 'POST /frames', 'POST /frames']);
    expect(server.accounts['alice'], [hallway]);
  });

  test('dev-mode email sign-in stays out of the directory', () async {
    await directory.add([kitchen], signedInWith: const PasswordCredential('a@dev.test', 'secret1'));
    await directory.remove([kitchen]);
    await directory.flush();
    expect(server.calls, isEmpty);
    expect(await store.read('directory'), isNull);
  });

  test('changes made offline go out at the next flush', () async {
    await directory.signIn(google('alice'));
    server.offline = true;
    await directory.add([kitchen]);
    await directory.remove([hallway]);
    expect(server.accounts['alice'], isNull);

    server.offline = false;
    await directory.flush();
    expect(server.accounts['alice'], [kitchen]);
    server.calls.clear();
    await directory.flush();
    expect(server.calls, isEmpty);
  });

  test('changes fired together are applied in order', () async {
    await directory.signIn(google('alice'));
    unawaited(directory.add([kitchen, hallway]));
    unawaited(directory.remove([kitchen]));
    await directory.flush();
    expect(server.accounts['alice'], [hallway]);
  });

  test('a token signed out elsewhere is dropped; changes wait for the next sign-in', () async {
    await directory.signIn(google('alice'));
    server.tokens.clear();
    await directory.add([kitchen]);
    expect(await savedToken(), isNull);
    expect(server.accounts['alice'], isNull);

    await directory.signIn(google('alice'));
    expect(server.accounts['alice'], [kitchen]);
  });

  test("a join that couldn't reach the directory is sent at the next sign-in", () async {
    server.offline = true;
    await directory.add([kitchen], signedInWith: google('alice'));
    server.offline = false;
    expect(await directory.signIn(google('alice')), [kitchen]);
  });

  test('sign out drops the token; delete my account forgets the account', () async {
    await directory.add([kitchen], signedInWith: google('alice'));
    await directory.signOut();
    expect(server.calls.last, 'POST /sign-out');
    expect(await store.read('directory'), isNull);
    expect(server.accounts['alice'], [kitchen]);

    await directory.signIn(google('alice'));
    await directory.forget();
    expect(server.calls.last, 'DELETE /me');
    expect(server.accounts['alice'], isNull);
    expect(await store.read('directory'), isNull);
  });

  test('off when no directory is configured', () async {
    final off = FrameDirectory(store, httpClient: server.client, baseUrl: '');
    expect(off.available, isFalse);
    await off.add([kitchen], signedInWith: google('alice'));
    await off.flush();
    expect(server.calls, isEmpty);
  });
}
