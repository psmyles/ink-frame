// The setup wizard's steps against the real Management API: creates a frame's project
// in the spare free slot with a personal access token, installs the bundled backend,
// signs in as its owner, then deletes it. Run with tools/dev/provision-live-test.ts
// (skipped otherwise).
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/backend_bundle.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/platform_api.dart';
import 'package:ink_frame/data/provisioner.dart';
import 'package:ink_frame/data/secure_store.dart';

/// The app's assets read from disk (the test binding, needed for rootBundle, would
/// block the real network calls this test makes).
class DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  final pat = Platform.environment['INKFRAME_PROVISION_PAT'];
  if (pat == null) {
    test('provisioning', () {}, skip: 'Run through tools/dev/provision-live-test.ts');
    return;
  }

  test('set up a frame end to end, then delete it', () async {
    final bundle = await BackendBundle.load(DiskBundle());
    final p = Provisioner(PlatformApi(() async => pat), bundle);
    final t0 = DateTime.now();
    void lap(String what) => stdout.writeln('[${DateTime.now().difference(t0).inSeconds}s] $what');

    final ref = await p.createProject(frameName: "Grandma's test", timezone: 'Asia/Kolkata');
    lap('created $ref');
    try {
      await p.waitUntilReady(ref);
      lap('ready');
      await p.installDatabase(ref);
      expect(await p.schemaVersion(ref), bundle.latestVersion);
      await p.installDatabase(ref); // again: nothing pending, still fine
      lap('database at version ${bundle.latestVersion}');
      await p.deployFunctions(ref);
      expect(await p.updateAvailable(ref), isFalse);
      lap('functions deployed; no update needed');
      await p.configureSignIn(ref, keepEmail: true);
      await p.describeFrame(ref, name: "Grandma's", modelId: 'reterminal-e1002', timezone: 'Asia/Kolkata');
      await p.describeFrame(ref, name: 'ignored', modelId: 'reterminal-e1002', timezone: 'UTC');
      lap('sign-in on, frame described');

      final address = await p.address(ref);
      expect(address.key, startsWith('sb_publishable_'));
      final repo = FramesRepository(MemoryStore());
      // Auth may take a moment to pick up the new settings.
      FrameConnection? conn;
      for (var i = 0; conn == null; i++) {
        try {
          conn = await repo.signIn(address, PasswordCredential('owner-$ref@test.invalid', 'pw-${ref}x'));
        } catch (e) {
          if (i == 5) rethrow;
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
      await p.setOwner(ref, userId: conn.userId!, displayName: 'Priya');
      await p.setOwner(ref, userId: conn.userId!, displayName: 'Priya'); // again: fine
      final summary = await conn.loadSummary();
      expect(summary.frame.name, "Grandma's");
      expect(summary.isMine, isTrue);
      expect(summary.owner.displayName, 'Priya');
      lap('signed in as owner');

      // The functions answer (an invite needs app-api and the owner).
      final invite = await conn.callApi('POST', '/invites', body: {'max_uses': 1, 'expires_in_s': 3600});
      expect((invite as Map)['code'], isA<String>());
      lap('app-api answers');
    } finally {
      await p.deleteFrame(ref);
      lap('deleted $ref');
    }
  });
}
