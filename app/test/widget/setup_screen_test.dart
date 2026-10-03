// Set up a frame (app-flow §1.3) against a fake Management API: the form, the
// checklist, signing in as owner, the 2-project limit, resuming and cancelling.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/setup/setup_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/state/setup.dart';
import 'package:ink_frame/theme/theme.dart';

import '../unit/fake_directory.dart';
import '../unit/fake_platform.dart';
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show priya;
import 'join_screen_test.dart' show FakeSignIn;

const ownerId = '6f1c2e2a-0b8e-4c55-9d7c-3f0b9a2d1e44';

/// Signs in to any frame as [ownerId] without a network (and without a Supabase
/// client, whose refresh timer would outlive the test).
class FakeConnection implements FrameConnection {
  FakeConnection(this.address, this.summary);

  @override
  final FrameAddress address;
  final FrameSummary summary;
  var _in = false;

  @override
  bool get isSignedIn => _in;
  @override
  String? get userId => _in ? ownerId : null;
  @override
  Future<bool> restore() async => _in;
  @override
  Future<void> signIn(Credential credential) async => _in = true;
  @override
  Future<void> signOut() async => _in = false;
  @override
  Future<FrameSummary> loadSummary() async => summary;
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Setup {
  Setup(this.platform, this.store, this.directory, this.repo);

  final FakePlatform platform;
  final MemoryStore store;
  final FakeDirectoryServer directory;
  final FramesRepository repo;
}

Future<Setup> open(WidgetTester tester, {FakePlatform? platform, bool connected = true, Map<String, String> saved = const {}}) async {
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = platform ?? FakePlatform();
  final store = MemoryStore()..values.addAll(saved);
  if (connected) {
    final expires = DateTime.now().add(const Duration(hours: 20)).millisecondsSinceEpoch;
    store.values['supabase_platform'] = jsonEncode({'access_token': 'a', 'refresh_token': 'r', 'expires_at': expires});
  }
  final summary = FakeFrameApi().view(priya, priya).summary!;
  final directory = FakeDirectoryServer();
  final repo = FramesRepository(store, connect: (a, _) => FakeConnection(a, summary));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const SetupScreen()),
    GoRoute(
      path: '/frame/:ref',
      builder: (_, s) => Scaffold(
        body: Text('Frame ${s.pathParameters['ref']}${s.uri.queryParameters['connect'] == '1' ? ', connect' : ''}'),
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      storeProvider.overrideWithValue(store),
      framesRepositoryProvider.overrideWithValue(repo),
      backendBundleProvider.overrideWith((ref) async => testBundle),
      provisionerProvider.overrideWith((ref) async => fake.provisioner()),
      signInServiceProvider.overrideWithValue(FakeSignIn('priya')),
      frameDirectoryProvider.overrideWithValue(directory.directory(store)),
    ],
    child: MaterialApp.router(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return Setup(fake, store, directory, repo);
}

Future<void> fillIn(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Kitchen');
  await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Priya');
  await tester.pump();
}

void main() {
  testWidgets('a new owner sets up a frame: checklist, sign in, ready', (tester) async {
    final t = await open(tester);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('reTerminal E1002 7.3"'), findsOneWidget);
    expect(find.text('800 × 480'), findsNWidgets(2));
    await tester.tap(find.text('Pimoroni Inky 7.3"'));
    await fillIn(tester);

    await tester.tap(find.text('Set up Kitchen'));
    await tester.pumpAndSettle();
    expect(find.text('Setting up Kitchen'), findsOneWidget);
    expect(find.textContaining('Sign in with the account you use Ink Frame with'), findsOneWidget);
    final project = t.platform.projects.values.single;
    expect(project.name, 'Ink Frame - Kitchen');
    expect(project.schemaVersion, 2);
    expect(project.deployed, ['device-api', 'app-api']);
    expect(project.frameName, 'Kitchen');
    expect(project.owner, isNull);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(project.owner, ownerId);
    expect(find.text('Kitchen is ready'), findsOneWidget);
    final address = (await FramesRepository(t.store).load()).single;
    expect(address.url, 'https://${project.ref}.supabase.co');
    expect(t.directory.accounts['priya'], [address]);
    expect(t.store.values['setup'], isNull);

    expect(find.text('Later — add photos first'), findsOneWidget);
    await tester.tap(find.text('Connect the frame'));
    await tester.pumpAndSettle();
    expect(find.text('Frame ${project.ref}, connect'), findsOneWidget);
  });

  testWidgets('not connected yet: Connect Supabase first', (tester) async {
    await open(tester, connected: false);
    expect(find.text('Connect Supabase'), findsOneWidget);
    await fillIn(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Set up Kitchen')).onPressed, isNull);
  });

  testWidgets('the free plan limit says what to do', (tester) async {
    final t = await open(tester, platform: FakePlatform(projectLimit: 0));
    await fillIn(tester);
    await tester.tap(find.text('Set up Kitchen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already runs 2 projects'), findsOneWidget);
    expect(find.text('Open Supabase'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(t.platform.projects, isEmpty);
  });

  testWidgets('a setup stopped half way continues where it stopped', (tester) async {
    final platform = FakePlatform();
    final ref = await platform.provisioner().createProject(frameName: 'Kitchen', timezone: 'UTC');
    final plan = SetupPlan(name: 'Kitchen', modelId: 'reterminal-e1002', timezone: 'UTC', displayName: 'Priya', ref: ref, done: {SetupStep.create});
    final t = await open(tester, platform: platform, saved: {'setup': jsonEncode(plan.toJson())});
    expect(find.text('Setting up Kitchen stopped before it finished.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(t.platform.projects.length, 1); // no second project
    expect(t.platform.projects[ref]!.frameName, 'Kitchen');
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('cancel deletes the half-made frame', (tester) async {
    final t = await open(tester);
    await fillIn(tester);
    await tester.tap(find.text('Set up Kitchen'));
    await tester.pumpAndSettle();
    expect(t.platform.projects, hasLength(1));

    await tester.tap(find.text('Cancel setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel setup'));
    await tester.pumpAndSettle();
    expect(t.platform.projects, isEmpty);
    expect(t.store.values['setup'], isNull);
    expect(find.text('Set up a frame'), findsWidgets);
  });
}
