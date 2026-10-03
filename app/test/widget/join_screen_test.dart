// Signing in on a new device (app-flow §1.4): Google/Apple finds your frames in the
// directory; a link or QR code is the fallback.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ink_frame/auth/sign_in_service.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_directory.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/join/join_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../unit/fake_directory.dart';
import '../unit/frame_directory_test.dart' show hallway, kitchen;

class FakeSignIn extends SignInService {
  FakeSignIn(this.account, {this.cancel = false});

  final String account;
  final bool cancel;

  @override
  List<SignInMethod> methods({required bool devMode}) => [SignInMethod.google, if (devMode) SignInMethod.password];

  @override
  Future<IdTokenCredential> google() async {
    if (cancel) throw const SignInCancelled();
    return IdTokenCredential(provider: OAuthProvider.google, idToken: account);
  }
}

/// Signs in to every frame except [notOn] (as if the frame said "not a member").
class FakeRepo extends FramesRepository {
  FakeRepo(super.store, {this.notOn = const []});

  final List<FrameAddress> notOn;
  final signedIn = <FrameAddress>[];

  @override
  Future<List<FrameAddress>> signInAll(List<FrameAddress> frames, Credential credential) async {
    for (final f in frames.where((f) => !notOn.contains(f))) {
      signedIn.add(f);
      await add(f);
    }
    return [for (final f in frames) if (notOn.contains(f)) f];
  }
}

Future<void> pump(
  WidgetTester tester, {
  required FakeDirectoryServer server,
  FakeSignIn? signIn,
  FakeRepo? repo,
  bool returning = true,
  FrameDirectory? directory,
}) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryStore();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => JoinScreen(returning: returning)),
    GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('Home'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      storeProvider.overrideWithValue(store),
      framesRepositoryProvider.overrideWithValue(repo ?? FakeRepo(store)),
      signInServiceProvider.overrideWithValue(signIn ?? FakeSignIn('alice')),
      frameDirectoryProvider.overrideWithValue(directory ?? server.directory(store)),
    ],
    child: MaterialApp.router(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a new device: sign in and your frames come back', (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen, hallway];
    final repo = FakeRepo(MemoryStore());
    await pump(tester, server: server, repo: repo);
    expect(find.text('Sign in with the account you used before, and your frames will appear.'), findsOneWidget);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(repo.signedIn, [kitchen, hallway]);
    expect(await repo.load(), [kitchen, hallway]);
  });

  testWidgets("frames you're no longer on are skipped and taken off your list", (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen, hallway];
    await pump(tester, server: server, repo: FakeRepo(MemoryStore(), notOn: [hallway]));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(server.accounts['alice'], [kitchen]);
  });

  testWidgets('no frames found says what to do', (tester) async {
    final server = FakeDirectoryServer();
    await pump(tester, server: server, signIn: FakeSignIn('bob'));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No frames found for this account.'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('offline', (tester) async {
    final server = FakeDirectoryServer()..offline = true;
    await pump(tester, server: server);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text("Can't look for your frames right now. Check your internet connection and try again."), findsOneWidget);
  });

  testWidgets('closing the sign-in sheet changes nothing', (tester) async {
    final server = FakeDirectoryServer();
    await pump(tester, server: server, signIn: FakeSignIn('alice', cancel: true));
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(server.calls, isEmpty);
    expect(find.textContaining('No frames'), findsNothing);
  });

  testWidgets('a link or QR code instead', (tester) async {
    await pump(tester, server: FakeDirectoryServer());
    await tester.tap(find.text('Use a link or QR code instead'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Invite link'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('without a directory, signing in starts with the link', (tester) async {
    final server = FakeDirectoryServer();
    await pump(tester, server: server, directory: FrameDirectory(MemoryStore(), httpClient: server.client, baseUrl: ''));
    expect(find.widgetWithText(TextField, 'Invite link'), findsOneWidget);
  });

  testWidgets('an invite starts with the link, as before', (tester) async {
    await pump(tester, server: FakeDirectoryServer(), returning: false);
    expect(find.text('Join a frame'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Invite link'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });
}
