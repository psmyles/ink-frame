// An asleep frame (PLAN.md §6.4): its owner gets "Wake up", which restores the
// project; others are told to ask the owner.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/frame/frame_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/frame_admin.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/state/setup.dart';
import 'package:ink_frame/theme/theme.dart';

import '../unit/fake_platform.dart';
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' as fs;
import 'layout_test.dart' show grandma;

Future<void> pump(WidgetTester tester, {required bool mine, required FakePlatform platform}) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      frameViewProvider(grandma).overrideWith((ref) async => FrameView(
            error: const ApiException(ApiException.asleep, ''),
            cached: CachedFrame("Grandma's", 'Priya', mine),
          )),
      photosProvider.overrideWith2((a) => fs.FakePhotos(a, const [])),
      frameModelProvider.overrideWith((ref, a) async => FrameModel(
            const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}),
            fs.palette,
          )),
      memberNamesProvider.overrideWith((ref, a) async => const {}),
      frameApiProvider.overrideWith((ref, a) => FakeFrameApi()),
      platformConnectedProvider.overrideWith((ref) async => true),
      provisionerProvider.overrideWith((ref) async => platform.provisioner()),
    ],
    child: MaterialApp(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const FrameScreen(address: grandma),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the owner wakes up an asleep frame', (tester) async {
    final platform = FakePlatform();
    platform.projects[grandma.ref] = FakeProject(grandma.ref, 'Ink Frame - Grandmas')..status = 'INACTIVE';
    await pump(tester, mine: true, platform: platform);
    expect(find.textContaining('photo storage is asleep'), findsOneWidget);

    await tester.tap(find.text('Wake up'));
    await tester.pumpAndSettle();
    expect(platform.projects[grandma.ref]!.status, 'ACTIVE_HEALTHY');
    expect(platform.calls, contains('POST /v1/projects/${grandma.ref}/restore'));
    expect(find.textContaining("Waking up Grandma's"), findsNothing);
  });

  testWidgets('others are told to ask the owner', (tester) async {
    await pump(tester, mine: false, platform: FakePlatform());
    expect(find.textContaining('Ask Priya to open Ink Frame'), findsOneWidget);
    expect(find.text('Wake up'), findsNothing);
  });
}
