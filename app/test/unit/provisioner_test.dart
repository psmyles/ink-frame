// The setup wizard's steps (PLAN.md §6.2–6.4) against a fake Management API: each
// step can run again, updates are only offered forwards, and the 2-project limit is
// recognised. The real API is covered by test/live/provision_live_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/backend_bundle.dart';
import 'package:ink_frame/data/platform_api.dart';
import 'package:ink_frame/data/provisioner.dart';

import 'fake_platform.dart';

const owner = '6f1c2e2a-0b8e-4c55-9d7c-3f0b9a2d1e44';

void main() {
  test('a whole setup, every step safe to run again', () async {
    final fake = FakePlatform();
    final p = fake.provisioner();
    final ref = await p.createProject(frameName: "Grandma's", timezone: 'Asia/Kolkata');
    final project = fake.projects[ref]!;
    expect(project.name, 'Ink Frame - Grandmas');

    await p.waitUntilReady(ref);
    for (var i = 0; i < 2; i++) {
      await p.installDatabase(ref);
      await p.deployFunctions(ref);
      await p.configureSignIn(ref);
      await p.describeFrame(ref, name: "Grandma's", modelId: 'reterminal-e1002', timezone: 'Asia/Kolkata');
      await p.setOwner(ref, userId: owner, displayName: "Priya's");
    }
    expect(project.schemaVersion, 2);
    expect(project.config, {'project_url': 'https://$ref.supabase.co', 'backend': 'fp-2'});
    expect(project.deployed, ['device-api', 'app-api', 'device-api', 'app-api']);
    expect(project.auth, {'external_google_enabled': true, 'external_email_enabled': false});
    expect(project.frameName, "Grandma's");
    expect(project.owner, owner);
    expect((await p.address(ref)).key, 'sb_publishable_$ref');
  });

  test('developer setups keep email sign-in', () async {
    final fake = FakePlatform();
    final p = fake.provisioner();
    final ref = await p.createProject(frameName: 'Dev', timezone: 'UTC');
    await p.configureSignIn(ref, keepEmail: true);
    expect(fake.projects[ref]!.auth, {'external_google_enabled': true, 'mailer_autoconfirm': true});
  });

  test('regions follow the time zone; project names stay plain', () {
    expect(Provisioner.regionFor('Asia/Kolkata'), 'apac');
    expect(Provisioner.regionFor('Australia/Sydney'), 'apac');
    expect(Provisioner.regionFor('America/New_York'), 'americas');
    expect(Provisioner.regionFor('Europe/Berlin'), 'emea');
    expect(Provisioner.regionFor('Africa/Lagos'), 'emea');
    expect(Provisioner.regionFor('UTC'), 'emea');
    expect(Provisioner.projectName('Kitchen'), 'Ink Frame - Kitchen');
    expect(Provisioner.projectName('🏡'), 'Ink Frame');
  });

  test('the free plan limit is recognised', () async {
    final fake = FakePlatform(projectLimit: 0);
    await expectLater(
      fake.provisioner().createProject(frameName: 'Kitchen', timezone: 'UTC'),
      throwsA(isA<PlatformApiException>().having((e) => e.code, 'code', PlatformApiException.projectLimit)),
    );
  });

  test('someone else already owns it', () async {
    final fake = FakePlatform();
    final p = fake.provisioner();
    final ref = await p.createProject(frameName: 'Kitchen', timezone: 'UTC');
    await p.setOwner(ref, userId: owner, displayName: 'Priya');
    await expectLater(
      p.setOwner(ref, userId: owner.replaceFirst('6', '7'), displayName: 'Mallory'),
      throwsA(isA<PlatformApiException>().having((e) => e.code, 'code', 'owner_exists')),
    );
  });

  test('updates: only forwards, and also for changed functions', () async {
    final fake = FakePlatform();
    final ref = await fake.provisioner().createProject(frameName: 'Kitchen', timezone: 'UTC');
    final project = fake.projects[ref]!;
    final older = fake.provisioner(const BackendBundle(
      migrations: [Migration(1, '-- 1')],
      seed: '',
      functions: {},
      models: [],
      auth: {},
      fingerprint: 'fp-1',
    ));
    await older.update(ref);
    expect(project.schemaVersion, 1);

    final p = fake.provisioner();
    expect(await p.updateAvailable(ref), isTrue); // newer schema
    await p.update(ref);
    expect(project.schemaVersion, 2);
    expect(await p.updateAvailable(ref), isFalse);

    project.config['backend'] = 'fp-other'; // same schema, other functions
    expect(await p.updateAvailable(ref), isTrue);

    project.schemaVersion = 3; // a newer app updated it: never go back
    expect(await p.updateAvailable(ref), isFalse);
  });

  test('wake up restores a paused frame and waits until it answers', () async {
    final fake = FakePlatform();
    final p = fake.provisioner();
    final ref = await p.createProject(frameName: 'Kitchen', timezone: 'UTC');
    await p.waitUntilReady(ref);
    fake.projects[ref]!.status = 'INACTIVE';
    await p.wakeUp(ref);
    expect(fake.projects[ref]!.status, 'ACTIVE_HEALTHY');
    expect(fake.calls, contains('POST /v1/projects/$ref/restore'));

    await p.deleteFrame(ref);
    expect(fake.projects, isEmpty);
  });

  test('a refused token asks to connect again', () async {
    final fake = FakePlatform()..failNext = 401;
    await expectLater(
      fake.provisioner().createProject(frameName: 'Kitchen', timezone: 'UTC'),
      throwsA(isA<PlatformApiException>().having((e) => e.code, 'code', PlatformApiException.reconnect)),
    );
  });
}
