// Settings, invites, people, names, storage and account deletion (Phase 3d) through
// the real backend. Run with `deno run --allow-all tools/dev/app-live-test.ts`.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_api.dart';
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
  final password = fx['password'] as String;

  Future<FrameConnection> signIn(Credential c) async {
    final repo = FramesRepository(MemoryStore());
    await repo.signIn(address, c);
    return repo.ready(address);
  }

  late FrameApi owner;

  setUpAll(() async {
    owner = FrameApi(await signIn(PasswordCredential(fx['owner_email'] as String, fx['owner_password'] as String)));
  });

  /// A new person (dev projects confirm sign-ups) who joins with a fresh invite.
  Future<FrameApi> newMember(String label, String name) async {
    final invite = await owner.createInvite();
    final conn = await signIn(PasswordCredential('app-$label-${DateTime.now().microsecondsSinceEpoch}@test.invalid', password));
    expect(await conn.acceptInvite(invite.code, name), Role.member);
    return FrameApi(conn);
  }

  test('settings, including the app-only battery warning', () async {
    var f = await owner.updateSettings({'image_interval_s': 7200, 'quiet_start': '22:30', 'quiet_end': '06:45'});
    expect((f.imageIntervalS, f.quietStart, f.quietEnd), (7200, '22:30', '06:45'));
    f = await owner.updateSettings({'low_battery_pct': 30});
    expect(f.lowBatteryPct, 30);
    f = await owner.updateSettings({'low_battery_pct': null, 'quiet_start': null, 'quiet_end': null, 'image_interval_s': 14400});
    expect((f.lowBatteryPct, f.hasQuietHours), (null, false));
    expect((await owner.rename('Hallway')).name, 'Hallway');
    expect((await owner.rename('Kitchen')).name, 'Kitchen');
    await expectLater(owner.updateSettings({'low_battery_pct': 99}), throwsA(isA<ApiException>()));
  });

  test('invites: make, list, revoke', () async {
    final invite = await owner.createInvite(maxUses: 10, expiresIn: const Duration(days: 1));
    expect(invite.code, matches(RegExp(r'^[0-9A-Z]{5}-[0-9A-Z]{5}$')));
    final listed = (await owner.invites()).where((i) => i.id == invite.id).single;
    expect((listed.maxUses, listed.uses), (10, 0));
    await owner.revokeInvite(invite.id);
    expect((await owner.invites()).map((i) => i.id), isNot(contains(invite.id)));
  });

  test('people: join, rename yourself, storage, leave', () async {
    final bob = await newMember('bob', 'Bob');
    final bobId = bob.conn.userId!;
    var people = await owner.members();
    expect(people.first.isOwner, isTrue);
    expect(people.map((m) => m.displayName), contains('Bob'));

    await bob.updateMe('Bobby');
    people = await bob.members();
    expect(people.singleWhere((m) => m.userId == bobId).displayName, 'Bobby');

    final ownerUsage = await owner.usage();
    expect(ownerUsage.freeTierBytes, 1024 * 1024 * 1024);
    expect(ownerUsage.users.length, greaterThanOrEqualTo(2));
    expect((await bob.usage()).users.map((u) => u.userId), [bobId]);

    // Members can't change settings or invite.
    await expectLater(bob.updateSettings({'low_battery_pct': 10}), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_owner')));
    await expectLater(bob.createInvite(), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_owner')));

    await bob.removeMember(bobId); // leave
    await expectLater(bob.conn.loadSummary(), throwsA(isA<ApiException>().having((e) => e.code, 'code', ApiException.notMember)));
  });

  test('the owner removes someone; someone deletes their account', () async {
    final cat = await newMember('cat', 'Cat');
    await owner.removeMember(cat.conn.userId!);
    expect((await owner.members()).map((m) => m.displayName), isNot(contains('Cat')));

    final dan = await newMember('dan', 'Dan');
    await dan.deleteMe(deletePhotos: true);
    expect((await owner.members()).map((m) => m.displayName), isNot(contains('Dan')));
    await expectLater(owner.deleteMe(), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'owner_must_delete_frame')));
  });
}
