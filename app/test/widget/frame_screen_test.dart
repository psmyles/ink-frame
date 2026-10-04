import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/frame/frame_screen.dart';
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/imaging/png_encoder.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/frame_admin.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';

import 'fake_frame_api.dart';

const kitchen = FrameAddress('https://aaaaaaaaaaaaaaaaaaaa.supabase.co', 'sb_publishable_aaaaaaaaaaaa');
const alice = Member(userId: 'alice', role: Role.member, displayName: 'Alice');
const priya = Member(userId: 'priya', role: Role.owner, displayName: 'Priya');

final palette = Palette.fromJson({
  'id': 'spectra6',
  'colors': [
    {'name': 'black', 'color': '#1F2226', 'deviceColor': '#000000'},
    {'name': 'white', 'color': '#B9C7C9', 'deviceColor': '#ffffff'},
  ],
});

FrameImage photo(String id, String? by, int pos) => FrameImage(
    id: id, uploadedBy: by, storagePath: '$id.png', bytes: 1000, position: pos.toDouble(), createdAt: DateTime.utc(2026, 9, pos));

FrameView view({required Member me, bool inOrder = false, bool connected = true}) => FrameView(
      summary: FrameSummary(
        frame: Frame(
          id: 'f',
          name: 'Kitchen',
          modelId: 'reterminal-e1002',
          connected: connected,
          upToDate: true,
          lastSeenAt: connected ? DateTime.now().subtract(const Duration(hours: 1)) : null,
          batteryPct: 90,
          fwVersion: '1',
          imageIntervalS: 14400,
          syncIntervalS: 86400,
          timezone: 'UTC',
          displayOrder: inOrder ? 'sequential' : 'random',
        ),
        me: me,
        owner: priya,
      ),
    );

class FakePhotos extends PhotosNotifier {
  FakePhotos(super.address, this.initial);

  final List<FrameImage> initial;
  final deleted = <String>[];

  @override
  Future<List<FrameImage>> build() async => initial;

  @override
  Future<void> delete(List<String> ids) async {
    deleted.addAll(ids);
    state = AsyncData([for (final i in state.value!) if (!ids.contains(i.id)) i]);
  }
}

late FakePhotos fake;

late FakeFrameApi api;

Future<void> pump(WidgetTester tester,
    {required Member me, List<FrameImage>? images, bool inOrder = false, Usage? storage, bool connected = true}) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final png = PngEncoder.encode(Uint8List(8 * 5), 8, 5, palette.deviceColors, zopfli: 0).bytes;
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      frameViewProvider(kitchen).overrideWith((ref) async => view(me: me, inOrder: inOrder, connected: connected)),
      photosProvider.overrideWith2((a) => fake = FakePhotos(a, images ?? [photo('a1', 'alice', 1), photo('p1', 'priya', 2), photo('a2', 'alice', 3)])),
      frameModelProvider.overrideWith((ref, a) async => FrameModel(
            const DeviceModel(id: 'reterminal-e1002', name: 'reTerminal', width: 800, height: 480, palette: {}),
            palette,
          )),
      displayBytesProvider.overrideWith((ref, key) async => png),
      memberNamesProvider.overrideWith((ref, a) async => {'alice': 'Alice', 'priya': 'Priya'}),
      frameApiProvider.overrideWith((ref, a) => api = FakeFrameApi(usage: storage)),
    ],
    child: MaterialApp(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const FrameScreen(address: kitchen),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('not connected yet: the owner gets Connect the frame, others don\'t', (tester) async {
    await pump(tester, me: priya, connected: false);
    expect(find.text('No frame connected yet'), findsOneWidget);
    expect(find.text('Connect the frame'), findsOneWidget);
    expect(find.textContaining('press the green button'), findsNothing);
  });

  testWidgets('not connected yet, as someone else: no Connect the frame', (tester) async {
    await pump(tester, me: alice, connected: false);
    expect(find.text('No frame connected yet'), findsOneWidget);
    expect(find.text('Connect the frame'), findsNothing);
  });

  testWidgets('keyboard: Cmd/Ctrl+A selects every photo; the Mac delete key asks to delete', (tester) async {
    await pump(tester, me: priya);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('Delete 3 photos from the album?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsNothing);
  });

  testWidgets('grid shows every photo and an add button', (tester) async {
    await pump(tester, me: alice);
    expect(find.byTooltip('Add photos'), findsOneWidget);
    expect(find.byType(InkWell).evaluate().length, greaterThanOrEqualTo(3));
    expect(find.text('Up to date · last checked 1 h ago'), findsOneWidget);
  });

  testWidgets("a member can't delete someone else's photo", (tester) async {
    await pump(tester, me: alice);
    final tiles = find.byType(InkWell);
    await tester.longPress(tiles.at(0));
    await tester.pump();
    await tester.tap(tiles.at(1)); // Priya's
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You can only delete your own photos'), findsOneWidget);
    expect(fake.deleted, isEmpty);
  });

  testWidgets('deleting your own photo asks first', (tester) async {
    await pump(tester, me: alice);
    await tester.longPress(find.byType(InkWell).at(2));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this photo from the album?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(fake.deleted, ['a2']);
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('the owner can delete anything', (tester) async {
    await pump(tester, me: priya);
    await tester.longPress(find.byType(InkWell).at(0));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(fake.deleted, ['a1']);
  });

  testWidgets('empty frame', (tester) async {
    await pump(tester, me: alice, images: []);
    expect(find.text('No photos yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add photos'), findsOneWidget);
  });

  testWidgets('change order: only the owner, only when in order', (tester) async {
    await pump(tester, me: priya, inOrder: true);
    expect(find.byTooltip('Change order'), findsOneWidget);
  });

  testWidgets('no change order for members or shuffle', (tester) async {
    await pump(tester, me: alice, inOrder: true);
    expect(find.byTooltip('Change order'), findsNothing);
  });
}
