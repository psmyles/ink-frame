// Frame settings (app-flow §4.3): the owner edits and each change saves at once;
// others read. The battery warning is app-only ("Saved", no "next check").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/battery/battery_watch.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/settings/settings_screen.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/data/backend_bundle.dart';
import 'package:ink_frame/state/setup.dart';

import '../unit/battery_watch_test.dart' show FakeNotifications, FakeWatchServer;
import '../unit/fake_platform.dart';
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show alice, kitchen, priya;

Future<FakeFrameApi> open(WidgetTester tester, {bool owner = true}) => pumpFrameScreen(
      tester,
      () => const SettingsScreen(address: kitchen),
      address: kitchen,
      me: owner ? priya : alice,
      owner: priya,
      // Tall enough for every row: the album, the frame, then how it shows photos.
      size: const Size(420, 2000),
    );

Future<void> choose(WidgetTester tester, String row, String option) async {
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text(option)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the owner sees every setting in plain words', (tester) async {
    await open(tester);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('4 hours'), findsOneWidget);
    expect(find.text('1 day · More often uses more battery.'), findsOneWidget);
    expect(find.text('Kolkata · Asia'), findsOneWidget);
    expect(find.text('20 % · Shows a warning when the battery drops below this.'), findsOneWidget);
    expect(find.text('reTerminal E1002'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);
    expect(find.text('Frame 1A2B'), findsOneWidget);
    expect(find.text('Connected · software 1.0.0 · Battery now: 80 %'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('312 MB of 1 GB'), 100);
    expect(find.text('312 MB of 1 GB'), findsOneWidget);
    expect(find.textContaining('Only'), findsNothing);
  });

  testWidgets('changing how often the photo changes saves at once', (tester) async {
    final api = await open(tester);
    await choose(tester, 'Change photo every', '2 hours');
    expect(api.calls, ['settings {image_interval_s: 7200}']);
    expect(find.text('Saved · the frame gets it at its next check'), findsOneWidget);
    expect(find.text('2 hours'), findsOneWidget);
  });

  testWidgets('the battery warning can be turned off; it only says Saved', (tester) async {
    final api = await open(tester);
    await choose(tester, 'Low battery warning', 'Off');
    expect(api.calls, ['settings {low_battery_pct: null}']);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Off · Shows a warning when the battery drops below this.'), findsOneWidget);

    // Closing the list without choosing changes nothing (Off is a choice, not "closed").
    await tester.tap(find.text('Low battery warning'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(api.calls, hasLength(1));
  });

  testWidgets('quiet hours: on with 22:00–07:00, then off', (tester) async {
    final api = await open(tester);
    await tester.tap(find.text('Quiet hours'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'settings {quiet_start: 22:00, quiet_end: 07:00}');
    expect(find.text('From'), findsOneWidget);
    expect(find.text('10:00 PM'), findsOneWidget);
    await tester.tap(find.text('Quiet hours'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'settings {quiet_start: null, quiet_end: null}');
    expect(find.text('From'), findsNothing);
  });

  testWidgets('order and time zone', (tester) async {
    final api = await open(tester);
    await tester.tap(find.text('In order'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'settings {display_order: sequential}');

    await tester.tap(find.text('Time zone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new york');
    await tester.pumpAndSettle();
    await tester.tap(find.text('New York'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'settings {timezone: America/New_York}');
    expect(find.text('New York · America'), findsOneWidget);
  });

  testWidgets('rename', (tester) async {
    final api = await open(tester);
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Hallway ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.calls, ['rename Hallway']);
    expect(find.text('Hallway'), findsOneWidget);
  });

  testWidgets('a failed save says so and shows the old value', (tester) async {
    final api = await open(tester);
    api.failNext = const ApiException('offline', 'No connection.');
    await choose(tester, 'Change photo every', '1 day');
    expect(find.text("Couldn't save. Try again."), findsOneWidget);
    expect(find.text('4 hours'), findsOneWidget);
  });

  testWidgets('others see the settings but can\'t change them', (tester) async {
    final api = await open(tester, owner: false);
    expect(find.text('Only Priya can change these settings.'), findsOneWidget);
    await tester.tap(find.text('Change photo every'));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    // Plain values, not greyed-out controls.
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget); // quiet hours
    expect(api.calls, isEmpty);
  });

  testWidgets('owner tools: update the frame, then delete it with its name typed', (tester) async {
    final platform = FakePlatform();
    platform.projects[kitchen.ref] = FakeProject(kitchen.ref, 'Ink Frame - Kitchen')
      ..status = 'ACTIVE_HEALTHY'
      ..schemaVersion = 1;
    final store = MemoryStore();
    await pumpFrameScreen(
      tester,
      () => const SettingsScreen(address: kitchen),
      address: kitchen,
      me: priya,
      owner: priya,
      store: store,
      overrides: [
        platformConnectedProvider.overrideWith((ref) async => true),
        provisionerProvider.overrideWith((ref) async => platform.provisioner()),
      ],
    );
    await tester.scrollUntilVisible(find.text('Delete this album'), 200);
    expect(find.text('Owner tools'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('An update for Kitchen is ready'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pumpAndSettle();
    expect(platform.projects[kitchen.ref]!.schemaVersion, 2);
    expect(find.text('Kitchen is up to date'), findsOneWidget);
    expect(find.text('An update for Kitchen is ready'), findsNothing);

    await tester.tap(find.text('Delete this album'));
    await tester.pumpAndSettle();
    final delete = find.widgetWithText(FilledButton, 'Delete');
    expect(tester.widget<FilledButton>(delete).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'kitchen');
    await tester.pump();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(platform.projects, isEmpty);
    expect(await FramesRepository(store).load(), isEmpty);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('owner tools without Supabase connected on this device', (tester) async {
    await open(tester);
    await tester.scrollUntilVisible(find.text('Delete this album'), 200);
    expect(find.textContaining('Not connected on this device'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('changing the model warns that the photos go', (tester) async {
    final api = await pumpFrameScreen(
      tester,
      () => const SettingsScreen(address: kitchen),
      address: kitchen,
      me: priya,
      owner: priya,
      overrides: [backendBundleProvider.overrideWith((ref) async => testBundle)],
    );
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test panel 7.3"'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Switch Kitchen to the Test panel 7.3"?'), findsOneWidget);
    expect(find.textContaining('photos will be removed'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(api.calls, ['model other-7-3']);
  });

  group('the memory card', () {
    const mb = 1024 * 1024, gb = 1024 * mb;
    Future<void> pumpWith(WidgetTester tester, Map<String, int?> card, {int photoBytes = 312 * mb}) => pumpFrameScreen(
          tester,
          () => const SettingsScreen(address: kitchen),
          address: kitchen,
          me: priya,
          owner: priya,
          size: const Size(420, 1400),
          api: FakeFrameApi(frame: frameJson(card: card), members: [priya], usage: sampleUsage(bytes: photoBytes)),
        );

    testWidgets('its size, what is used, and what the photos take', (tester) async {
      await pumpWith(tester, {'sd_total_bytes': 32 * gb, 'sd_free_bytes': 30 * gb, 'cache_bytes': 312 * mb});
      expect(find.text('Memory card'), findsOneWidget);
      expect(find.text('2 GB of 32 GB used · its photos take 312 MB'), findsOneWidget);
      expect(find.textContaining("don't all fit"), findsNothing);
    });

    testWidgets("photos that don't fit say by how much", (tester) async {
      // 100 MB free + 50 MB of photos on it − 8 MB kept free = 142 MB of room for 312 MB.
      await pumpWith(tester, {'sd_total_bytes': 256 * mb, 'sd_free_bytes': 100 * mb, 'cache_bytes': 50 * mb});
      expect(find.textContaining("Kitchen's photos don't all fit on the frame's memory card (170 MB too much)."), findsOneWidget);
    });

    testWidgets('no card, or one it cannot read', (tester) async {
      await pumpWith(tester, {'sd_total_bytes': 0, 'sd_free_bytes': null, 'cache_bytes': null});
      expect(find.textContaining("No memory card, or the frame can't read it."), findsOneWidget);
    });

    testWidgets('not reported (older firmware): no row', (tester) async {
      await pumpWith(tester, {});
      expect(find.text('Memory card'), findsNothing);
    });
  });

  testWidgets('with one model there is nothing to change to', (tester) async {
    await pumpFrameScreen(
      tester,
      () => const SettingsScreen(address: kitchen),
      address: kitchen,
      me: priya,
      owner: priya,
      overrides: [
        backendBundleProvider.overrideWith((ref) async => BackendBundle(
              migrations: const [],
              seed: '',
              functions: const {},
              models: [testBundle.models.first],
              auth: const {},
              fingerprint: '',
            )),
      ],
    );
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('the frame: connect a different one, or disconnect (the photos stay)', (tester) async {
    final api = await open(tester);
    await tester.scrollUntilVisible(find.text('Connect a different frame'), 200);
    await tester.ensureVisible(find.text('Disconnect'));
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The photos stay in Kitchen'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();
    expect(api.calls, ['disconnect']);
    expect(find.text('No frame connected yet'), findsOneWidget);
    expect(find.text('Connect the frame'), findsOneWidget);
    expect(find.text('Disconnect'), findsNothing);
  });

  Future<(FakeFrameApi, FakeWatchServer, FakeNotifications)> withNotify(WidgetTester tester,
      {bool owner = true, bool allow = true, int? warning = 20}) async {
    final server = FakeWatchServer();
    final notifications = FakeNotifications(allow: allow);
    final api = await pumpFrameScreen(
      tester,
      () => const SettingsScreen(address: kitchen),
      address: kitchen,
      me: owner ? priya : alice,
      owner: priya,
      api: FakeFrameApi(frame: {...frameJson(), 'low_battery_pct': warning}, members: [priya, alice]),
      overrides: [
        batteryWatchProvider.overrideWithValue(BatteryWatch(MemoryStore(), httpClient: server.client)),
        notificationsProvider.overrideWithValue(notifications),
      ],
    );
    await tester.scrollUntilVisible(find.text("Notify me when it's low"), 200);
    return (api, server, notifications);
  }

  bool switchOn(WidgetTester tester) => tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, "Notify me when it's low")).value;

  testWidgets('notify me when the battery is low: on for the owner, can be turned off', (tester) async {
    final (api, server, _) = await withNotify(tester);
    expect(switchOn(tester), isTrue);
    expect(find.text('On this phone.'), findsOneWidget);

    await tester.tap(find.text("Notify me when it's low"));
    await tester.pumpAndSettle();
    expect(switchOn(tester), isFalse);
    expect(server.revoked, isEmpty, reason: 'no token was made yet in this test');
  });

  testWidgets('others turn it on themselves; the phone asks for permission', (tester) async {
    final (api, _, notifications) = await withNotify(tester, owner: false);
    expect(switchOn(tester), isFalse);
    await tester.tap(find.text("Notify me when it's low"));
    await tester.pumpAndSettle();
    expect(switchOn(tester), isTrue);
    expect(notifications.asked, 1);
    expect(api.watchTokens, hasLength(1));
  });

  testWidgets('notifications blocked, or the warning off: it says so', (tester) async {
    await withNotify(tester, allow: false);
    expect(find.textContaining('Notifications are off for Ink Frame'), findsOneWidget);
  });

  testWidgets('with the warning off there is nothing to notify about', (tester) async {
    await withNotify(tester, warning: null);
    expect(switchOn(tester), isFalse);
    expect(find.text('Turn on the low battery warning first.'), findsOneWidget);
  });

  testWidgets('others see no owner tools and no Change', (tester) async {
    await open(tester, owner: false);
    await tester.scrollUntilVisible(find.text('Storage'), 200);
    expect(find.text('Owner tools'), findsNothing);
    expect(find.text('Change'), findsNothing);
    expect(find.text('Disconnect'), findsNothing);
    expect(find.text('Connect a different frame'), findsNothing);
  });
}
