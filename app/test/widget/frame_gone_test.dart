// A frame that no longer exists (its project was deleted): the banner says so, and
// "Remove from this device" takes it off this device and off your account's list,
// so other devices stop offering it. Its Home card says "No longer exists".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ink_frame/battery/battery_watch.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/frame/frame_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/frame_admin.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';
import 'package:ink_frame/widgets/status_line.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;

import '../unit/fake_directory.dart';
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' as fs show FakePhotos, palette;
import 'frame_screen_test.dart' show kitchen;

const gone = FrameView(
  error: ApiException(ApiException.gone, 'The frame no longer exists.'),
  cached: CachedFrame('Kitchen', 'Priya', false),
);

Widget app(Widget child) => MaterialApp(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('Remove from this device: off this device and off the account\'s list', (tester) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryStore();
    final repo = FramesRepository(store);
    await repo.add(kitchen);
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen];
    final directory = server.directory(store);
    await directory.signIn(const IdTokenCredential(provider: OAuthProvider.google, idToken: 'alice'));

    final router = GoRouter(initialLocation: '/frame', routes: [
      GoRoute(path: '/frame', builder: (_, _) => const FrameScreen(address: kitchen)),
      GoRoute(path: '/home', builder: (_, _) => const Text('Home page')),
    ]);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        storeProvider.overrideWithValue(store),
        framesRepositoryProvider.overrideWithValue(repo),
        frameDirectoryProvider.overrideWithValue(directory),
        batteryWatchProvider.overrideWithValue(BatteryWatch(MemoryStore(), supported: false)),
        frameViewProvider(kitchen).overrideWith((ref) async => gone),
        photosProvider.overrideWith2((a) => fs.FakePhotos(a, const [])),
        frameModelProvider.overrideWith((ref, a) async => FrameModel(
              const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}),
              fs.palette,
            )),
        memberNamesProvider.overrideWith((ref, a) async => const {}),
        frameApiProvider.overrideWith((ref, a) => FakeFrameApi()),
      ],
      child: MaterialApp.router(
        theme: InkTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Kitchen no longer exists: its photo storage was deleted.'), findsOneWidget);

    await tester.tap(find.text('Remove from this device'));
    await tester.pumpAndSettle();
    expect(find.text('Home page'), findsOneWidget);
    expect(await repo.load(), isEmpty);
    expect(server.accounts['alice'], isEmpty);
  });

  testWidgets('the Home card says it no longer exists', (tester) async {
    await tester.pumpWidget(app(const StatusLine(gone)));
    expect(find.text('No longer exists'), findsOneWidget);
  });
}
