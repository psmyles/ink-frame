// Account (app-flow §7.2): your name on every frame, another device, delete account.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_frame/data/backend_bundle.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/platform_api.dart';
import 'package:ink_frame/data/provisioner.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/account/account_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/frame_admin.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/state/setup.dart';
import 'package:ink_frame/theme/theme.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../unit/fake_directory.dart';
import '../unit/frame_directory_test.dart' show google;
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show alice, kitchen, priya;

const grandma = FrameAddress('https://bbbbbbbbbbbbbbbbbbbb.supabase.co', 'sb_publishable_bbbbbbbbbbbb');
const aliceOwner = Member(userId: 'alice', role: Role.owner, displayName: 'Alice');

/// Management API calls made (owner tools); answers 200.
final platformCalls = <String>[];

/// Alice on Kitchen (Priya's) and on Grandma's (hers if [ownsGrandma], else Priya's).
Future<(FakeFrameApi, FakeFrameApi, MemoryStore)> open(WidgetTester tester, {bool ownsGrandma = false, FakeDirectoryServer? server}) async {
  platformCalls.clear();
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryStore();
  final repo = FramesRepository(store);
  await repo.add(kitchen);
  await repo.add(grandma);
  final directory = (server ?? FakeDirectoryServer()).directory(store);
  if (server != null) await directory.signIn(google('alice'));
  final k = FakeFrameApi(members: [priya, alice]);
  final g = FakeFrameApi(frame: frameJson(name: "Grandma's"), members: [if (ownsGrandma) aliceOwner else priya, if (!ownsGrandma) alice]);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const AccountScreen()),
    GoRoute(path: '/welcome', builder: (_, _) => const Scaffold(body: Text('Welcome'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      storeProvider.overrideWithValue(store),
      frameApiProvider.overrideWith((ref, a) => a == kitchen ? k : g),
      frameViewProvider(kitchen).overrideWith((ref) async => k.view(alice, priya)),
      frameViewProvider(grandma).overrideWith((ref) async => ownsGrandma ? g.view(aliceOwner, aliceOwner) : g.view(alice, priya)),
      memberNamesProvider.overrideWith((ref, a) async => const {}),
      frameDirectoryProvider.overrideWithValue(directory),
      platformConnectedProvider.overrideWith((ref) async => true),
      provisionerProvider.overrideWith((ref) async => Provisioner(
            PlatformApi(() async => 'token', httpClient: MockClient((req) async {
              platformCalls.add('${req.method} ${req.url.path}');
              return http.Response('', 200);
            })),
            const BackendBundle(migrations: [], seed: '', functions: {}, models: [], auth: {}, fingerprint: ''),
          )),
    ],
    child: MaterialApp.router(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return (k, g, store);
}

void main() {
  testWidgets('changing your name changes it on every frame', (tester) async {
    final (k, g, store) = await open(tester);
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Your name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ali');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(k.calls, ['me Ali']);
    expect(g.calls, ['me Ali']);
    expect(find.text('Name updated'), findsOneWidget);
    expect(await FramesRepository(store).lastDisplayName(), 'Ali');
  });

  testWidgets('use on another device: a QR code and link with every frame, no invite code', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await open(tester);
    await tester.tap(find.text('Use on another device'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('Already use Ink Frame? Sign in'), findsOneWidget);
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    final link = FrameLink.parse(copied!)!;
    expect(link.frames, [kitchen, grandma]);
    expect(link.isInvite, isFalse);
  });

  testWidgets('deleting your account leaves every frame after typing DELETE', (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen, grandma];
    final (k, g, store) = await open(tester, server: server);
    await tester.scrollUntilVisible(find.text('Delete my account'), 100);
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(find.text('• Kitchen'), findsOneWidget);
    expect(find.text("• Grandma's"), findsOneWidget);
    final delete = find.widgetWithText(FilledButton, 'Delete account');
    expect(tester.widget<FilledButton>(delete).onPressed, isNull);
    await tester.tap(find.text('Also delete my photos'));
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(k.calls, ['deleteMe photos=true']);
    expect(g.calls, ['deleteMe photos=true']);
    expect(await FramesRepository(store).load(), isEmpty);
    expect(find.text('Welcome'), findsOneWidget);
    // The directory forgets you too.
    expect(server.calls.last, 'DELETE /me');
    expect(server.accounts['alice'], isNull);
  });

  testWidgets('signing out forgets the frames on this device, not on your list', (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen, grandma];
    final (_, _, store) = await open(tester, server: server);
    await tester.scrollUntilVisible(find.text('Sign out'), 100);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(await FramesRepository(store).load(), isEmpty);
    expect(server.calls.last, 'POST /sign-out');
    expect(server.tokens, isEmpty);
    expect(server.accounts['alice'], [kitchen, grandma]);
  });

  testWidgets("deleting your account also deletes the frames you set up", (tester) async {
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen, grandma];
    final (k, g, store) = await open(tester, ownsGrandma: true, server: server);
    await tester.scrollUntilVisible(find.text('Delete my account'), 100);
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('These frames you set up are deleted'), findsOneWidget);
    expect(find.text("• Grandma's"), findsOneWidget);
    expect(find.text('• Kitchen'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
    await tester.pumpAndSettle();
    expect(platformCalls, ['DELETE /v1/projects/${grandma.ref}']);
    expect(g.calls, isEmpty); // deleted with its project, not left
    expect(k.calls, ['deleteMe photos=false']);
    expect(await FramesRepository(store).load(), isEmpty);
    expect(server.accounts['alice'], isNull);
    expect(find.text('Welcome'), findsOneWidget);
  });
}
