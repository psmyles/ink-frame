// Joins the dev frame through the real backend. Run with
// `deno run --allow-all tools/dev/app-live-test.ts`, which sets up the frame and
// passes it in INKFRAME_LIVE; skipped otherwise.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/secure_store.dart';

void main() {
  final raw = Platform.environment['INKFRAME_LIVE'];
  if (raw == null) {
    test('live tests', () {}, skip: 'Run through tools/dev/app-live-test.ts');
    return;
  }
  final fx = jsonDecode(raw) as Map<String, dynamic>;
  final address = FrameAddress(fx['url'] as String, fx['key'] as String);
  final member = PasswordCredential(fx['member_email'] as String, fx['password'] as String);
  final outsider = PasswordCredential(fx['outsider_email'] as String, fx['password'] as String);
  final invite = FrameLink([address], fx['code'] as String).toHttps();

  test('join with a pasted invite link, then see the frame', () async {
    final store = MemoryStore();
    final repo = FramesRepository(store);

    final link = FrameLink.parse(invite)!;
    expect(link.isInvite, isTrue);
    await repo.signIn(link.frames.single, member);
    expect(await repo.join(link.frames.single, link.code!, 'Alice'), Role.member);
    expect(await repo.load(), [address]);
    expect(await repo.lastDisplayName(), 'Alice');

    final s = await (await repo.ready(address)).loadSummary();
    expect(s.frame.name, 'Kitchen');
    expect(s.frame.connected, isFalse);
    expect(s.frame.upToDate, isFalse);
    expect(s.me.displayName, 'Alice');
    expect(s.owner.displayName, 'Priya');
    expect(s.isMine, isFalse);

    // A new run restores the saved session from the store.
    final again = FramesRepository(store);
    final c = await again.ready(address);
    expect(c.isSignedIn, isTrue);
    expect((await c.loadSummary()).me.displayName, 'Alice');

    // Accepting again is harmless (already a member).
    expect(await c.acceptInvite(link.code!, 'Alice'), Role.member);
  });

  test('a new device signs in with a "Use on another device" link', () async {
    final repo = FramesRepository(MemoryStore());
    final link = FrameLink.parse(FrameLink([address]).toHttps())!;
    expect(link.isInvite, isFalse);
    expect(await repo.signInAll(link.frames, member), 0);
    expect(await repo.load(), [address]);
    expect((await repo.cached(address))!.ownerName, 'Priya');
  });

  test('frames you are not on are skipped', () async {
    final repo = FramesRepository(MemoryStore());
    expect(await repo.signInAll([address], outsider), 1);
    expect(await repo.load(), isEmpty);
  });

  test('a wrong invite code is refused', () async {
    final repo = FramesRepository(MemoryStore());
    await repo.signIn(address, outsider);
    await expectLater(
      repo.join(address, 'ZZZZZ-ZZZZZ', 'Mallory'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_invite')),
    );
    expect(await repo.load(), isEmpty);
  });

  test('a wrong password is a sign-in error, not a new account', () async {
    final repo = FramesRepository(MemoryStore());
    await expectLater(
      repo.signIn(address, PasswordCredential(member.email, 'wrong-password')),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiException.signInFailed)),
    );
  });

  test('signing out forgets the frame and the session', () async {
    final store = MemoryStore();
    final repo = FramesRepository(store);
    await repo.signInAll([address], member);
    await repo.signOutAll();
    expect(await repo.load(), isEmpty);
    expect(store.values.keys.where((k) => k.startsWith('session:') || k.startsWith('cache:')), isEmpty);
  });
}
