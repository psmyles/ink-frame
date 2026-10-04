// First run (app-flow §1.1): sign in first. The account's frames come back from the
// directory (§1.4); with none, set up a frame or join with an invite, using the
// same sign-in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_directory.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/welcome/welcome_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../unit/fake_directory.dart';
import '../unit/frame_directory_test.dart' show hallway, kitchen;
import 'join_screen_test.dart' show FakeRepo, FakeSignIn;

late ProviderContainer container;

Future<void> pump(
  WidgetTester tester, {
  required FakeDirectoryServer server,
  FakeSignIn? signIn,
  FakeRepo? repo,
  FrameDirectory? directory,
  Credential? recent,
  bool devMode = false,
}) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryStore();
  if (devMode) store.values['dev_mode'] = 'true';
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const WelcomeScreen()),
    GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('Home'))),
    GoRoute(path: '/join', builder: (_, _) => const Scaffold(body: Text('Join'))),
    GoRoute(path: '/setup', builder: (_, _) => const Scaffold(body: Text('Setup'))),
  ]);
  addTearDown(router.dispose);
  container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      storeProvider.overrideWithValue(store),
      framesRepositoryProvider.overrideWithValue(repo ?? FakeRepo(store)),
      signInServiceProvider.overrideWithValue(signIn ?? FakeSignIn('alice')),
      frameDirectoryProvider.overrideWithValue(directory ?? server.directory(store)),
    ],
  );
  addTearDown(container.dispose);
  if (recent != null) container.read(lastCredentialProvider.notifier).set(recent);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> continueWithGoogle(WidgetTester tester) async {
  await tester.tap(find.text('Continue with Google'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sign in first, and your frames come back', (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen, hallway];
    final repo = FakeRepo(MemoryStore());
    await pump(tester, server: server, repo: repo);
    expect(find.text("I've been invited"), findsNothing);
    expect(find.text('Set up a frame'), findsNothing);

    await continueWithGoogle(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(repo.signedIn, [kitchen, hallway]);
    expect(await repo.load(), [kitchen, hallway]);
  });

  testWidgets("frames you're no longer on are skipped and taken off your list", (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen, hallway];
    await pump(tester, server: server, repo: FakeRepo(MemoryStore(), notOn: [hallway]));
    await continueWithGoogle(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(server.accounts['alice'], [kitchen]);
  });

  testWidgets('no frames: set up a frame or join with an invite, with the same sign-in', (tester) async {
    await pump(tester, server: FakeDirectoryServer(), signIn: FakeSignIn('bob'));
    await continueWithGoogle(tester);
    expect(find.text('No frames yet'), findsOneWidget);
    expect(find.textContaining('There are no frames on this account yet.'), findsOneWidget);
    expect(find.text('Set up a frame'), findsOneWidget);
    expect(container.read(lastCredentialProvider.notifier).fresh, isA<IdTokenCredential>());

    await tester.tap(find.text("I've been invited"));
    await tester.pumpAndSettle();
    expect(find.text('Join'), findsOneWidget);
  });

  testWidgets('frames that were all removed or deleted count as none', (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen];
    await pump(tester, server: server, repo: FakeRepo(MemoryStore(), notOn: [kitchen]));
    await continueWithGoogle(tester);
    expect(find.text('No frames yet'), findsOneWidget);
    expect(server.accounts['alice'], isEmpty);
  });

  testWidgets("offline: says it couldn't look, still offers both, and looks again", (tester) async {
    final server = FakeDirectoryServer()..offline = true;
    await pump(tester, server: server);
    await continueWithGoogle(tester);
    expect(find.text("Can't look for your frames right now. Check your internet connection and try again."), findsOneWidget);
    expect(find.text("I've been invited"), findsOneWidget);
    expect(find.text('Set up a frame'), findsOneWidget);

    server
      ..offline = false
      ..accounts['alice'] = [kitchen];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('an asleep frame: says so, and setting up or joining stays possible', (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen];
    await pump(tester, server: server, repo: FakeRepo(MemoryStore(), error: const ApiException(ApiException.asleep, '')));
    await continueWithGoogle(tester);
    expect(find.textContaining('This frame is asleep'), findsOneWidget);
    expect(find.text('Set up a frame'), findsOneWidget);
  });

  testWidgets('closing the sign-in sheet changes nothing', (tester) async {
    final server = FakeDirectoryServer();
    await pump(tester, server: server, signIn: FakeSignIn('alice', cancel: true));
    await continueWithGoogle(tester);
    expect(server.calls, isEmpty);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Set up a frame'), findsNothing);
  });

  testWidgets('use a different account: back to signing in, and Google asks which account', (tester) async {
    final signIn = FakeSignIn('bob');
    await pump(tester, server: FakeDirectoryServer(), signIn: signIn);
    await continueWithGoogle(tester);
    await tester.tap(find.text('Use a different account'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(signIn.signedOut, 1);
    expect(container.read(lastCredentialProvider), isNull);
  });

  testWidgets('without a directory: straight to set up or join', (tester) async {
    final server = FakeDirectoryServer();
    await pump(tester, server: server, directory: FrameDirectory(MemoryStore(), httpClient: server.client, baseUrl: ''));
    await continueWithGoogle(tester);
    expect(find.text('No frames yet'), findsOneWidget);
    expect(find.textContaining('There are no frames on this account'), findsNothing);
    expect(server.calls, isEmpty);
  });

  testWidgets('developer mode: email sign-in, which the directory doesn\'t know', (tester) async {
    final server = FakeDirectoryServer();
    await pump(tester, server: server, devMode: true);
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'alice@dev.test');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Set up a frame'), findsOneWidget);
    expect(server.calls, isEmpty);
    expect(container.read(lastCredentialProvider.notifier).fresh, isA<PasswordCredential>());
  });

  testWidgets('back here with a recent sign-in (left your last frame): set up or join', (tester) async {
    await pump(
      tester,
      server: FakeDirectoryServer(),
      recent: const IdTokenCredential(provider: OAuthProvider.google, idToken: 'alice'),
    );
    expect(find.text('Set up a frame'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });
}
