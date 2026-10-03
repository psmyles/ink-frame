// Frame settings (app-flow §4.3): the owner edits and each change saves at once;
// others read. The battery warning is app-only ("Saved", no "next check").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/features/settings/settings_screen.dart';

import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show alice, kitchen, priya;

Future<FakeFrameApi> open(WidgetTester tester, {bool owner = true}) => pumpFrameScreen(
      tester,
      () => const SettingsScreen(address: kitchen),
      address: kitchen,
      me: owner ? priya : alice,
      owner: priya,
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
    expect(find.text('Connected · software 1.0.0'), findsOneWidget);
    expect(find.text('Battery now: 80 %'), findsOneWidget);
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
}
