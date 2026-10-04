// Joining with a link (app-flow §1.2, §1.4). Finding your frames by signing in is
// on Welcome (welcome_screen_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ink_frame/auth/sign_in_service.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_connection.dart';
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
  var signedOut = 0;

  @override
  List<SignInMethod> methods({required bool devMode}) => [SignInMethod.google, if (devMode) SignInMethod.password];

  @override
  Future<void> signOut() async => signedOut++;

  @override
  Future<IdTokenCredential> google() async {
    if (cancel) throw const SignInCancelled();
    return IdTokenCredential(provider: OAuthProvider.google, idToken: account);
  }
}

/// Signs in to every frame except [notOn] (as if the frame said "not a member"), or
/// fails with [error].
class FakeRepo extends FramesRepository {
  FakeRepo(super.store, {this.notOn = const [], this.error});

  final List<FrameAddress> notOn;
  final ApiException? error;
  final signedIn = <FrameAddress>[];

  @override
  Future<List<FrameAddress>> signInAll(List<FrameAddress> frames, Credential credential) async {
    if (error != null) throw error!;
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
  bool returning = false,
  String? link,
  Credential? recent,
}) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryStore();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => JoinScreen(returning: returning, initialLink: link)),
    GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('Home'))),
  ]);
  addTearDown(router.dispose);
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      storeProvider.overrideWithValue(store),
      framesRepositoryProvider.overrideWithValue(repo ?? FakeRepo(store)),
      signInServiceProvider.overrideWithValue(signIn ?? FakeSignIn('alice')),
      frameDirectoryProvider.overrideWithValue(server.directory(store)),
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

void main() {
  testWidgets('an invite starts with the link', (tester) async {
    await pump(tester, server: FakeDirectoryServer());
    expect(find.text('Join a frame'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Invite link'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('"Sign in again" on a frame starts with the link too', (tester) async {
    await pump(tester, server: FakeDirectoryServer(), returning: true);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Invite link'), findsOneWidget);
  });

  testWidgets('without a recent sign-in, a link asks to sign in', (tester) async {
    await pump(tester, server: FakeDirectoryServer(), link: FrameLink([kitchen]).toHttps());
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('signed in on Welcome just now: a link signs in without asking again', (tester) async {
    final repo = FakeRepo(MemoryStore());
    await pump(
      tester,
      server: FakeDirectoryServer(),
      repo: repo,
      link: FrameLink([kitchen, hallway]).toHttps(),
      recent: const IdTokenCredential(provider: OAuthProvider.google, idToken: 'alice'),
    );
    expect(find.text('Home'), findsOneWidget);
    expect(repo.signedIn, [kitchen, hallway]);
  });
}
