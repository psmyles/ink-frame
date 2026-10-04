// Draws the app icon from FrameMark (not part of CI):
//   ICON=1 flutter test test/tool/app_icon_test.dart && dart run flutter_launcher_icons
// → assets/icon/*.png, then every platform's icon sizes (pubspec.yaml).
@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/theme/theme.dart';
import 'package:ink_frame/widgets/frame_mark.dart';

const paper = Color(0xFFF7F5F0);

Future<void> render(WidgetTester tester, String path, Widget child) async {
  tester.view.physicalSize = const Size(1024, 1024);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(Theme(
    data: InkTheme.light(),
    child: RepaintBoundary(key: key, child: SizedBox.expand(child: child)),
  ));
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  if (Platform.environment['ICON'] == null) {
    test('app icon', () {}, skip: 'Set ICON=1');
    return;
  }

  // iOS, Android (older launchers), Windows: the full square; iOS rounds it.
  testWidgets('icon', (t) => render(t, 'assets/icon/icon.png',
      const ColoredBox(color: paper, child: Center(child: FrameMark(size: 700)))));

  // Android adaptive icon: the mark inside the 66 % circle every mask keeps.
  testWidgets('foreground', (t) => render(t, 'assets/icon/foreground.png',
      const Center(child: FrameMark(size: 520))));

  // macOS: no mask, so the tile's rounded shape and margin are drawn here.
  testWidgets('macos', (t) => render(
        t,
        'assets/icon/icon_macos.png',
        Center(
          child: Container(
            width: 824,
            height: 824,
            decoration: BoxDecoration(
              color: paper,
              borderRadius: BorderRadius.circular(185),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))],
            ),
            alignment: Alignment.center,
            child: const FrameMark(size: 560),
          ),
        ),
      ));
}
