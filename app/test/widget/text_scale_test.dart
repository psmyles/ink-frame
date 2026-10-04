// Text at 200 % (app-flow §8.3): the main screens lay out without overflowing at
// phone size. An overflow fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/features/settings/settings_screen.dart';
import 'package:ink_frame/features/welcome/welcome_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/theme/theme.dart';

import '../unit/fake_bluetooth.dart';
import 'connect_frame_test.dart' as connect;
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' as frame show pump;
import 'frame_screen_test.dart' show alice, kitchen, priya;
import 'more_frames_test.dart' as more;
import 'setup_screen_test.dart' as setup;

void main() {
  void bigText(WidgetTester tester) {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Scrolls the first scrollable to the end, so every row is built and laid out.
  Future<void> scrollAll(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 30; i++) {
      await tester.drag(scrollable, const Offset(0, -300), warnIfMissed: false);
      await tester.pump();
    }
  }

  testWidgets('Welcome', (tester) async {
    bigText(tester);
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WelcomeScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text("I've been invited"), findsOneWidget);
  });

  testWidgets('Home with a frame and the "more frames" card', (tester) async {
    bigText(tester);
    await more.open(tester);
    expect(find.text('Add to this device'), findsOneWidget);
  });

  testWidgets('a frame with photos, as its owner', (tester) async {
    bigText(tester);
    await frame.pump(tester, me: priya);
    expect(find.byTooltip('Add photos'), findsOneWidget);
  });

  testWidgets('a frame not connected yet', (tester) async {
    bigText(tester);
    await frame.pump(tester, me: priya, connected: false);
    expect(find.text('Connect the frame'), findsOneWidget);
  });

  testWidgets('Settings, owner and others', (tester) async {
    bigText(tester);
    await pumpFrameScreen(tester, () => const SettingsScreen(address: kitchen), address: kitchen, me: priya, owner: priya);
    await scrollAll(tester);
    await pumpFrameScreen(tester, () => const SettingsScreen(address: kitchen), address: kitchen, me: alice, owner: priya);
    await scrollAll(tester);
  });

  testWidgets('Set up a frame: the form', (tester) async {
    bigText(tester);
    await setup.open(tester);
    await scrollAll(tester);
  });

  testWidgets('Connect the frame: get ready, then Wi-Fi', (tester) async {
    bigText(tester);
    await connect.open(tester, FakeBluetooth());
    expect(find.text('Get the frame ready'), findsOneWidget);
    await tester.ensureVisible(find.text('Find the frame'));
    await connect.findAndPair(tester);
    expect(find.text('Which Wi-Fi should the frame use?'), findsOneWidget);
    await scrollAll(tester);
  });
}
