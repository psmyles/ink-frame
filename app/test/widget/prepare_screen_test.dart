import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/prepare/prepare_screen.dart';
import 'package:ink_frame/features/prepare/source_photo.dart';
import 'package:ink_frame/imaging/pipeline.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/theme/theme.dart';

import 'frame_screen_test.dart' show kitchen, palette;

class RecordingQueue extends UploadQueue {
  RecordingQueue(super.address);

  final jobs = <PhotoJob>[];

  @override
  void addAll(List<PhotoJob> j) => jobs.addAll(j);
}

Future<SourcePhoto> sourcePhoto(WidgetTester tester, int w, int h) async {
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    rgba.setAll(i * 4, [(i % w) * 255 ~/ w, (i ~/ w) * 255 ~/ h, 128, 255]);
  }
  final image = await tester.runAsync(() {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  });
  return SourcePhoto('test.jpg', rgba, w, h, image!);
}

void main() {
  testWidgets('Automatic by default, Adjust collapsed, Upload queues the crop', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final photos = [await sourcePhoto(tester, 1200, 900), await sourcePhoto(tester, 600, 900)];
    late RecordingQueue queue;
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        frameModelProvider.overrideWith((ref, a) async => FrameModel(
              const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}),
              palette,
            )),
        uploadQueueProvider.overrideWith2((a) => queue = RecordingQueue(a)),
      ],
      child: MaterialApp(
        theme: InkTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => PrepareScreen(address: kitchen, photos: photos),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Prepare 2 photos'), findsOneWidget);
    expect(find.text('Adjust'), findsOneWidget);
    // Collapsed: no technical words or sliders visible.
    expect(find.text('Brightness'), findsNothing);
    expect(find.text('Dot pattern'), findsNothing);

    await tester.tap(find.text('Adjust'));
    await tester.pumpAndSettle();
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Dot pattern'), findsNothing); // still behind More options

    await tester.tap(find.text('Upload 2'));
    await tester.pumpAndSettle();
    expect(queue.jobs, hasLength(2));
    final first = queue.jobs.first;
    expect(first.adjustments.automatic, isTrue);
    expect((first.outWidth, first.outHeight), (800, 480));
    // Centre crop of 1200×900 to 5:3: full width, 720 tall.
    expect([first.crop!.w, first.crop!.h], [1200, 720]);
    expect(find.text('Prepare 2 photos'), findsNothing);
  });
}
