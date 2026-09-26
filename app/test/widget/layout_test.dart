// The layout follows window width only (app-flow §2.3): the same app shows the
// phone layout in a narrow window and two panes in a wide one.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/app.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/state/providers.dart';

import 'frame_screen_test.dart' as fs;

const kitchen = FrameAddress('https://aaaaaaaaaaaaaaaaaaaa.supabase.co', 'sb_publishable_aaaaaaaaaaaa');
const grandma = FrameAddress('https://bbbbbbbbbbbbbbbbbbbb.supabase.co', 'sb_publishable_bbbbbbbbbbbb');

FrameView view(String name, {required bool mine, bool upToDate = true}) {
  final me = Member(userId: 'me', role: mine ? Role.owner : Role.member, displayName: 'Alice');
  return FrameView(
    summary: FrameSummary(
      frame: Frame(
        id: name,
        name: name,
        modelId: 'reterminal-e1002',
        connected: true,
        upToDate: upToDate,
        lastSeenAt: DateTime.now().subtract(const Duration(hours: 3)),
        batteryPct: 80,
        fwVersion: '1.0.0',
        imageIntervalS: 14400,
        syncIntervalS: 86400,
        timezone: 'UTC',
      ),
      me: me,
      owner: mine ? me : const Member(userId: 'p', role: Role.owner, displayName: 'Priya'),
    ),
  );
}

Future<void> pumpApp(WidgetTester tester, Size size, {List<FrameAddress> frames = const []}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemoryStore();
  final repo = FramesRepository(store);
  for (final f in frames) {
    await repo.add(f);
  }
  await tester.pumpWidget(ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store),
      frameViewProvider(kitchen).overrideWith((ref) async => view('Kitchen', mine: true)),
      frameViewProvider(grandma).overrideWith((ref) async => FrameView(
            error: const ApiException(ApiException.asleep, ''),
            cached: const CachedFrame("Grandma's", 'Priya', false),
          )),
      photosProvider.overrideWith2((a) => fs.FakePhotos(a, const [])),
      frameModelProvider.overrideWith((ref, a) async => FrameModel(
            const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}),
            fs.palette,
          )),
      memberNamesProvider.overrideWith((ref, a) async => const {}),
    ],
    retry: (_, _) => null,
    child: const InkFrameApp(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no frames: Welcome', (tester) async {
    await pumpApp(tester, const Size(400, 800));
    expect(find.text("I've been invited"), findsOneWidget);
    expect(find.text('Set up a frame'), findsOneWidget);
  });

  testWidgets('narrow window: the phone layout, a list of frame cards', (tester) async {
    await pumpApp(tester, const Size(420, 860), frames: [kitchen, grandma]);
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.textContaining('Up to date'), findsOneWidget);
    expect(find.text("Grandma's"), findsOneWidget);
    expect(find.text('Set up by Priya'), findsOneWidget);
    expect(find.text('Asleep'), findsOneWidget);
    expect(find.text('Choose a frame'), findsNothing);

    await tester.tap(find.text('Kitchen'));
    await tester.pumpAndSettle();
    expect(find.text('To show changes now, press the green button on the frame.'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('wide window: sidebar and detail', (tester) async {
    await pumpApp(tester, const Size(1200, 800), frames: [kitchen, grandma]);
    expect(find.text('FRAMES'), findsOneWidget);
    expect(find.text('Choose a frame'), findsOneWidget);

    await tester.tap(find.text("Grandma's"));
    await tester.pumpAndSettle();
    expect(find.textContaining('is asleep because it wasn\'t used for a while. Ask Priya'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('narrowing a wide window switches to the phone layout', (tester) async {
    await pumpApp(tester, const Size(1200, 800), frames: [kitchen]);
    expect(find.text('FRAMES'), findsOneWidget);
    tester.view.physicalSize = const Size(600, 800);
    await tester.pumpAndSettle();
    expect(find.text('FRAMES'), findsNothing);
    expect(find.text('Kitchen'), findsOneWidget);
  });
}
