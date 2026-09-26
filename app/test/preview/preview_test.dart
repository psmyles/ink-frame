// Renders screens to PNGs for a visual check (not part of CI):
//   PREVIEW=1 flutter test test/preview --update-goldens   → test/preview/out/*.png (gitignored)
@Tags(['preview'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
