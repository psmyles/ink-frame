import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/prepare/frame_canvas.dart';
import 'package:ink_frame/features/prepare/prepare_screen.dart';
import 'package:ink_frame/features/prepare/prepare_session.dart';
import 'package:ink_frame/features/prepare/source_photo.dart';
import 'package:ink_frame/imaging/od_pipeline.dart' show OdSettings;
import 'package:ink_frame/imaging/pipeline.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/theme/theme.dart';

import 'frame_screen_test.dart' show kitchen, palette;

class RecordingQueue extends UploadQueue {
  RecordingQueue(super.address);

  @override
  void addAll(List<PhotoJob> j) => queued.addAll(j);
}

Future<ui.Image> decode(WidgetTester tester, Uint8List rgba, int w, int h) async => (await tester.runAsync(() {
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
      return c.future;
    }))!;

Future<SourcePhoto> sourcePhoto(WidgetTester tester, int w, int h) async {
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    rgba.setAll(i * 4, [(i % w) * 255 ~/ w, (i ~/ w) * 255 ~/ h, 128, 255]);
  }
  return SourcePhoto('test.jpg', rgba, w, h, await decode(tester, rgba, w, h));
}

/// Everything sent to the upload queue in the current test.
late List<PhotoJob> queued;
late List<PhotoJob> rendered, tuned;

/// What the fake search "finds" (one instance, so a re-search that finds the same
/// settings doesn't need a new render).
const tunedSettings = OdSettings(exposure: 1.1);

/// Opens Prepare from a button (so it can pop) with a fake renderer and queue.
Future<void> openPrepare(WidgetTester tester, Size size, List<SourcePhoto> photos,
    {Tuning Function(PhotoJob)? tune, bool settle = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final look = await decode(tester, Uint8List(800 * 480 * 4)..fillRange(0, 800 * 480 * 4, 200), 800, 480);
  rendered = [];
  tuned = [];
  queued = [];
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      frameModelProvider.overrideWith((ref, a) async => FrameModel(
            const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}),
            palette,
          )),
      uploadQueueProvider.overrideWith2(RecordingQueue.new),
      previewEngineProvider.overrideWithValue(PreviewEngine(
        render: (job, palette) async {
          rendered.add(job);
          return look;
        },
        tune: (job) {
          tuned.add(job);
          return tune?.call(job) ?? Tuning(Future.value(tunedSettings), () {});
        },
      )),
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('several photos: overview of frame looks, edit one, upload all', (tester) async {
    await openPrepare(tester, const Size(420, 900), [await sourcePhoto(tester, 1200, 900), await sourcePhoto(tester, 600, 900)]);

    expect(find.text('Prepare'), findsOneWidget);
    expect(find.text("How they'll look on the frame. Tap one to adjust."), findsOneWidget);
    expect(find.text('Edit'), findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, 'Add more photos'), findsOneWidget);
    // Both previews without opening anything: a quick look each, then Automatic's
    // search for each, then the tuned look.
    expect(tuned, hasLength(2));
    expect(rendered, hasLength(4));
    expect(rendered.where((j) => identical(j.autoSettings, tunedSettings)), hasLength(2));
    expect(find.text('Preparing…'), findsNothing);
    // No adjustments on the overview.
    expect(find.text('Brightness'), findsNothing);

    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    expect(find.text('Photo 1 of 2'), findsOneWidget);
    expect(find.textContaining('Drag the photo to move it.'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Dot pattern'), findsNothing); // behind More options

    // Holding "compare" shows the original.
    final hold = await tester.startGesture(tester.getCenter(find.text('View original')));
    await tester.pump();
    expect(find.text('Original'), findsOneWidget);
    await hold.up();
    await tester.pump();
    expect(find.text('Original'), findsNothing);

    // Dragging the photo down moves the crop up (centre crop of 1200×900 starts at y = 90).
    await tester.drag(find.byType(FrameCanvas), const Offset(0, 40));
    await tester.pumpAndSettle();
    // One quick render with the last settings; the search for the new crop finds
    // the same ones, so no second render.
    expect(rendered, hasLength(5));
    expect(identical(rendered.last.autoSettings, tunedSettings), isTrue);
    expect(tuned, hasLength(3));

    // A slider change keeps showing the last frame look (no flash back to the
    // photo) until the new one arrives moments later.
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await tester.pump();
    expect(tester.widget<FrameCanvas>(find.byType(FrameCanvas)).preview, isNotNull);
    expect(find.text('Updating…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Updating…'), findsNothing);
    expect(rendered, hasLength(6));
    expect(tuned, hasLength(3)); // sliders don't need a new search

    await tester.tap(find.byTooltip('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('Photo 2 of 2'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare'), findsOneWidget);

    await tester.tap(find.text('Upload 2'));
    await tester.pumpAndSettle();
    expect(queued, hasLength(2));
    final first = queued.first;
    expect(first.adjustments.automatic, isTrue);
    expect((first.outWidth, first.outHeight), (800, 480));
    expect([first.crop!.w, first.crop!.h], [1200, 720]);
    expect(first.crop!.y, lessThan(90));
    expect(first.adjustments.brightness, greaterThan(0));
    expect(identical(first.autoSettings, tunedSettings), isTrue); // Upload doesn't search again
    // Untouched: the centre crop of 600×900 to 5:3 (full width, 360 tall).
    expect([queued[1].crop!.y, queued[1].crop!.h], [270, 360]);
    expect(find.text('Prepare'), findsNothing);
  });

  testWidgets('one photo opens straight in the editor', (tester) async {
    await openPrepare(tester, const Size(420, 900), [await sourcePhoto(tester, 1200, 900)]);
    expect(find.text('Prepare'), findsOneWidget);
    expect(find.byType(FrameCanvas), findsOneWidget);
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Use for all'), findsNothing);
    expect(find.text('Start over'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(queued, hasLength(1));
  });

  testWidgets('leaving with several photos asks first', (tester) async {
    await openPrepare(tester, const Size(420, 900), [await sourcePhoto(tester, 800, 600), await sourcePhoto(tester, 800, 600)]);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Leave without uploading?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare'), findsNothing);
    expect(queued, isEmpty);
  });

  testWidgets('moving the crop stops a search under way; quick looks never wait for it', (tester) async {
    final cancelled = <int>[];
    await openPrepare(
      tester,
      const Size(420, 900),
      [await sourcePhoto(tester, 1200, 900)],
      // Searches that never finish on their own.
      tune: (job) {
        final n = tuned.length;
        return Tuning(Completer<OdSettings>().future, () => cancelled.add(n));
      },
      settle: false,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(rendered, hasLength(1)); // the quick look, without waiting for the search
    expect(tuned, hasLength(1));

    await tester.drag(find.byType(FrameCanvas), const Offset(0, 40));
    await tester.pump();
    expect(cancelled, [1]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(rendered, hasLength(2)); // the new crop's quick look
    expect(tuned, hasLength(1)); // the new search waits for the crop to be still
    await tester.pump(const Duration(seconds: 1));
    expect(tuned, hasLength(2));

    // Upload with no finished search: the upload queue searches itself.
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(queued.single.autoSettings, isNull);
    expect(cancelled, [1, 2]); // leaving stops the last one
  });

  // Small phone, phone, phone landscape, tablet, desktop: no overflow, and the
  // canvas and Adjust are both on screen without scrolling the canvas away.
  for (final size in const [Size(360, 640), Size(420, 900), Size(860, 400), Size(1024, 1366), Size(1400, 900)]) {
    testWidgets('fits at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      await openPrepare(tester, size, [await sourcePhoto(tester, 1200, 900), await sourcePhoto(tester, 900, 1200)]);
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byType(FrameCanvas));
      expect(canvas.height, greaterThan(150));
      expect(canvas.bottom, lessThanOrEqualTo(size.height));
      expect(find.text('Automatic').hitTestable(), findsOneWidget);
    });
  }
}
