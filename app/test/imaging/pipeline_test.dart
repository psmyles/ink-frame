import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ink_frame/imaging/dither.dart';
import 'package:ink_frame/imaging/fidelity.dart';
import 'package:ink_frame/imaging/od_pipeline.dart';
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/imaging/pipeline.dart';
import 'package:ink_frame/imaging/resize.dart';

final spectra6 = Palette.fromJson({
  'id': 'spectra6',
  'colors': [
    for (final (c, d) in [('#1F2226', '#000000'), ('#B9C7C9', '#ffffff'), ('#233F8E', '#0000ff'), ('#35563A', '#00ff00'), ('#62201E', '#ff0000'), ('#C1BB1E', '#ffff00')])
      {'name': d, 'color': c, 'deviceColor': d},
  ],
});

Uint8List photo(int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      out[i] = (x * 255 ~/ w);
      out[i + 1] = (y * 255 ~/ h);
      out[i + 2] = (128 + 100 * math.sin(x / 40.0)).toInt();
      out[i + 3] = 255;
    }
  }
  return out;
}

void main() {
  test('centre crop matches getCroppedCanvas()', () {
    final wide = CropRect.center(1600, 800, 800 / 480);
    // Values from running the getCroppedCanvas() arithmetic in Node.
    expect([wide.x, wide.y, wide.w, wide.h], [133.33333333333326, 0, 1333.3333333333335, 800]);
    final tall = CropRect.center(1000, 1500, 800 / 480);
    expect([tall.x, tall.y, tall.w, tall.h], [0, 450, 1000, 600]);
  });

  test('resize keeps flat colours and averages detail', () {
    final flat = Uint8List(40 * 20 * 4);
    for (var i = 0; i < flat.length; i += 4) {
      flat.setAll(i, [10, 200, 30, 255]);
    }
    final out = cropResize(flat, 40, 20, const CropRect(0, 0, 40, 20), 13, 7);
    for (var i = 0; i < out.length; i += 4) {
      expect(out.sublist(i, i + 4), [10, 200, 30, 255]);
    }
    // A 1-pixel checkerboard shrunk 4× becomes mid grey (no aliasing).
    final checker = Uint8List(64 * 64 * 4);
    for (var i = 0; i < 64 * 64; i++) {
      final v = ((i % 64) + (i ~/ 64)).isEven ? 255 : 0;
      checker.setAll(i * 4, [v, v, v, 255]);
    }
    final small = cropResize(checker, 64, 64, const CropRect(0, 0, 64, 64), 16, 16);
    for (var i = 0; i < small.length; i += 4) {
      expect(small[i], inInclusiveRange(120, 135));
    }
  });

  test('rotate', () {
    // 2×1: red, blue.
    final rgba = Uint8List.fromList([255, 0, 0, 255, 0, 0, 255, 255]);
    final (r1, w1, h1) = rotate(rgba, 2, 1, 1);
    expect((w1, h1), (1, 2));
    expect(r1, [255, 0, 0, 255, 0, 0, 255, 255]); // red on top
    final (r2, _, _) = rotate(rgba, 2, 1, 2);
    expect(r2, [0, 0, 255, 255, 255, 0, 0, 255]);
    final (r3, w3, h3) = rotate(rgba, 2, 1, 3);
    expect((w3, h3), (1, 2));
    expect(r3, [0, 0, 255, 255, 255, 0, 0, 255]); // blue on top
  });

  test('photo to frame PNG', () {
    final job = PhotoJob(rgba: photo(1600, 1000), width: 1600, height: 1000, outWidth: 800, outHeight: 480, palette: spectra6);
    final p = preparePhoto(job, zopfliIterations: 2);
    expect(p.sha256, sha256.convert(p.png).toString());
    final decoded = img.decodePng(p.png)!;
    expect((decoded.width, decoded.height), (800, 480));
    // Pixels are the device colours of the dithered indices.
    for (var i = 0; i < p.indices.length; i += 997) {
      final px = decoded.getPixel(i % 800, i ~/ 800);
      expect([px.r, px.g, px.b], spectra6.deviceColors[p.indices[i]]);
    }
    expect(p.png.length, lessThan(512 * 1024)); // the bucket's limit
  });

  test('sliders move settings the right way', () {
    const base = OdSettings(exposure: 1, saturation: 1, strength: 0);
    expect(settingsFor(const PhotoAdjustments(brightness: 1), base).exposure, greaterThan(1.3));
    expect(settingsFor(const PhotoAdjustments(brightness: -1), base).exposure, lessThan(0.75));
    expect(settingsFor(const PhotoAdjustments(colour: 1), base).saturation, 1.5);
    expect(settingsFor(const PhotoAdjustments(colour: -1), base).saturation, 0.5);
    expect(settingsFor(const PhotoAdjustments(contrast: 1), base).strength, closeTo(0.6, 1e-9));
    expect(settingsFor(const PhotoAdjustments(contrast: -1), base).strength, 0);
    expect(settingsFor(const PhotoAdjustments(pattern: DotPattern.smooth), base).algorithm, 'jarvis');
    expect(settingsFor(const PhotoAdjustments(pattern: DotPattern.crisp), base).algorithm, 'atkinson');
  });

  test('Automatic is closer to the source than plain dithering', () {
    final src = photo(400, 240);
    final auto = preparePhoto(
      PhotoJob(rgba: src, width: 400, height: 240, outWidth: 400, outHeight: 240, palette: spectra6),
      zopfliIterations: 0,
    );
    final fid = Fidelity(src, 400, 240, spectra6);
    final plain = errorDiffusion(src, 400, 240, spectra6.colors, 'floydSteinberg', true);
    // A synthetic full-gamut gradient; real photos gain far more (fidelity_bench_test.dart).
    expect(fid.score(auto.indices), lessThan(fid.score(plain)));
  });

  test('every dot pattern produces a valid image', () {
    for (final pattern in DotPattern.values) {
      final job = PhotoJob(
        rgba: photo(200, 120),
        width: 200,
        height: 120,
        outWidth: 100,
        outHeight: 60,
        palette: spectra6,
        adjustments: PhotoAdjustments(automatic: false, pattern: pattern),
      );
      final p = preparePhoto(job, zopfliIterations: 1, random: math.Random(1).nextDouble);
      expect(img.decodePng(p.png)!.width, 100, reason: '$pattern');
      expect(p.indices.toSet().length, greaterThan(2), reason: '$pattern');
    }
  });

  test('reusing Automatic settings gives the same result', () {
    final job = PhotoJob(rgba: photo(300, 180), width: 300, height: 180, outWidth: 150, outHeight: 90, palette: spectra6);
    final (first, tuned) = ditherPhoto(job);
    final again = PhotoJob(
        rgba: job.rgba, width: 300, height: 180, outWidth: 150, outHeight: 90, palette: spectra6, autoSettings: tuned);
    expect(ditherPhoto(again).$1, first);
  });
}
