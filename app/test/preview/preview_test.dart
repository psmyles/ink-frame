// Renders screens to PNGs for a visual check (not part of CI):
//   PREVIEW=1 flutter test test/preview --update-goldens   → test/preview/out/*.png (gitignored)
@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/frame/frame_screen.dart';
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/imaging/pipeline.dart';
import 'package:ink_frame/imaging/png_encoder.dart';
import 'package:ink_frame/imaging/png_palette.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';

import '../widget/frame_screen_test.dart' as fs;
import '../widget/prepare_screen_test.dart' as ps;
import 'package:ink_frame/features/prepare/prepare_screen.dart';
import '../widget/layout_test.dart' as layout;

Future<void> loadFonts() async {
  // flutter test sets FLUTTER_ROOT.
  final fonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('$fonts/Roboto-$w.ttf');
    if (f.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void main() {
  if (Platform.environment['PREVIEW'] == null) {
    test('previews', () {}, skip: 'Set PREVIEW=1 and pass --update-goldens');
    return;
  }
  setUpAll(loadFonts);

  Future<void> shot(WidgetTester tester, String name) =>
      expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));

  testWidgets('welcome', (t) async {
    await layout.pumpApp(t, const Size(400, 820));
    await shot(t, 'welcome');
  });
  testWidgets('home narrow', (t) async {
    await layout.pumpApp(t, const Size(400, 820), frames: [layout.kitchen, layout.grandma]);
    await shot(t, 'home_narrow');
  });
  testWidgets('home wide', (t) async {
    await layout.pumpApp(t, const Size(1200, 760), frames: [layout.kitchen, layout.grandma]);
    await t.tap(find.text("Grandma's"));
    await t.pumpAndSettle();
    await shot(t, 'home_wide');
  });

  testWidgets('frame grid with real photos', (t) async {
    final dir = Platform.environment['PHOTOS'];
    if (dir == null) return;
    final pal = Palette.fromJson({
      'id': 'spectra6',
      'colors': [
        for (final (n, c, d) in [('black', '#1F2226', '#000000'), ('white', '#B9C7C9', '#ffffff'), ('blue', '#233F8E', '#0000ff'),
          ('green', '#35563A', '#00ff00'), ('red', '#62201E', '#ff0000'), ('yellow', '#C1BB1E', '#ffff00')])
          {'name': n, 'color': c, 'deviceColor': d},
      ],
    });
    final files = (Directory(dir).listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path))).take(5).toList();
    final shown = <String, Uint8List>{};
    final images = <FrameImage>[];
    await t.runAsync(() async {
      for (final (i, f) in files.indexed) {
        final src = img.decodeImage(f.readAsBytesSync())!.convert(numChannels: 4);
        final p = preparePhoto(
          PhotoJob(rgba: src.getBytes(order: img.ChannelOrder.rgba), width: src.width, height: src.height, outWidth: 800, outHeight: 480, palette: pal),
          zopfliIterations: 0,
        );
        shown['p$i'] = recolorPng(PngEncoder.encode(p.indices, 800, 480, pal.deviceColors, zopfli: 0).bytes, pal.deviceColors, pal.colors);
        images.add(fs.photo('p$i', i.isEven ? 'alice' : 'priya', i + 1));
      }
    });
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        frameViewProvider(fs.kitchen).overrideWith((ref) async => fs.view(me: fs.alice)),
        photosProvider.overrideWith2((a) => fs.FakePhotos(a, images)),
        frameModelProvider.overrideWith((ref, a) async =>
            FrameModel(const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}), pal)),
        displayBytesProvider.overrideWith((ref, key) async => shown[key.$2.id]!),
        memberNamesProvider.overrideWith((ref, a) async => {'alice': 'Alice', 'priya': 'Priya'}),
      ],
      child: MaterialApp(
        theme: InkTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FrameScreen(address: fs.kitchen),
      ),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pumpAndSettle();
    for (final e in find.byType(Image).evaluate()) {
      await t.runAsync(() => precacheImage((e.widget as Image).image, e));
    }
    await t.pumpAndSettle();
    await shot(t, 'frame_grid');
  });

  testWidgets('prepare with Adjust open', (t) async {
    t.view.physicalSize = const Size(420, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final photos = [await ps.sourcePhoto(t, 1200, 900), await ps.sourcePhoto(t, 900, 1200)];
    await t.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        frameModelProvider.overrideWith((ref, a) async =>
            FrameModel(const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}), fs.palette)),
      ],
      child: MaterialApp(
        theme: InkTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrepareScreen(address: fs.kitchen, photos: photos),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Adjust'));
    await t.pumpAndSettle();
    await t.tap(find.text('More options'));
    await t.pumpAndSettle();
    await shot(t, 'prepare');
  });
}
