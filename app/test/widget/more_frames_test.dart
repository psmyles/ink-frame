// Frames set up or joined on another device show up on Home as "1 more frame is on
// your account" (app-flow §1.4); Add to this device signs in again and adds them.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/home/home_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../unit/fake_directory.dart';
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show kitchen, priya;
import 'join_screen_test.dart' show FakeRepo, FakeSignIn;

const hallway = FrameAddress('https://cccccccccccccccccccc.supabase.co', 'sb_publishable_cccccccccccc');

/// Kitchen on this device; the account (directory) has Kitchen and Hallway.
Future<(FakeRepo, FakeDirectoryServer)> open(WidgetTester tester, {bool signedInToDirectory = true, bool dark = false}) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryStore();
  final repo = FakeRepo(store);
  await repo.add(kitchen);
  final server = FakeDirectoryServer()..accounts['priya'] = [kitchen];
  final directory = server.directory(store);
  if (signedInToDirectory) {
    await directory.signIn(const IdTokenCredential(provider: OAuthProvider.google, idToken: 'priya'));
  }
  server.accounts['priya']!.add(hallway);
  final view = FakeFrameApi().view(priya, priya);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      storeProvider.overrideWithValue(store),
      framesRepositoryProvider.overrideWithValue(repo),
      frameDirectoryProvider.overrideWithValue(directory),
      signInServiceProvider.overrideWithValue(FakeSignIn('priya')),
      frameViewProvider.overrideWith((ref, a) async => view),
    ],
    child: MaterialApp(
      theme: dark ? InkTheme.dark() : InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomeScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return (repo, server);
}

void main() {
  testWidgets('a frame added on another device: Add to this device', (tester) async {
    final (repo, _) = await open(tester);
    expect(find.text('1 more frame is on your account'), findsOneWidget);
    expect(find.textContaining('added on another device'), findsOneWidget);

    await tester.tap(find.text('Add to this device'));
    await tester.pumpAndSettle();
    expect(repo.signedIn, [hallway]);
    expect(await repo.load(), [kitchen, hallway]);
    expect(find.text('1 more frame is on your account'), findsNothing);
  });

  testWidgets('Not now puts it away', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('1 more frame is on your account'), findsNothing);
  });

  testWidgets('without a directory sign-in (dev-mode email) nothing is asked', (tester) async {
    final (_, server) = await open(tester, signedInToDirectory: false);
    expect(find.text('1 more frame is on your account'), findsNothing);
    expect(server.calls, isEmpty);
  });
}
