// Automatic's search in its own isolate (Prepare's slow lane): finishes with the
// same settings as running it directly, and can be stopped part-way.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/features/prepare/prepare_session.dart';
import 'package:ink_frame/imaging/auto.dart';
import 'package:ink_frame/imaging/pipeline.dart';

import '../widget/frame_screen_test.dart' show palette;

PhotoJob job() {
  const w = 400, h = 300;
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    rgba.setAll(i * 4, [(i % w) * 255 ~/ w, (i ~/ w) * 255 ~/ h, 90, 255]);
  }
  return PhotoJob(rgba: rgba, width: w, height: h, outWidth: 800, outHeight: 480, palette: palette);
}

void main() {
  test('finds the same settings as a direct search', () async {
    final j = job();
    final direct = autoSettings(frameSized(j), 800, 480, palette);
    final found = await tuneInIsolate(j).result.timeout(const Duration(seconds: 30));
    expect([found.exposure, found.saturation, found.strength, found.shadowBoost],
        [direct.exposure, direct.saturation, direct.strength, direct.shadowBoost]);
  });

  test('stopping it never delivers a result', () async {
    final t = tuneInIsolate(job());
    var finished = false;
    unawaited(t.result.then((_) => finished = true, onError: (_) => finished = true));
    t.cancel();
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(finished, isFalse);
  });
}
