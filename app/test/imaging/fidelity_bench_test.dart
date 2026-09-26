// Which processing gets closest to the source (lib/imaging/fidelity.dart)?
//   PHOTOS=<dir> [OUT=<dir>] flutter test test/imaging/fidelity_bench_test.dart
@Tags(['bench'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ink_frame/imaging/autotune.dart';
import 'package:ink_frame/imaging/color_space.dart';
import 'package:ink_frame/imaging/fidelity.dart';
import 'package:ink_frame/imaging/od_pipeline.dart';
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/imaging/resize.dart';

Palette pal(String id, List<(String, List<int>, List<int>)> c) =>
    Palette(id: id, names: [for (final e in c) e.$1], colors: [for (final e in c) e.$2], deviceColors: [for (final e in c) e.$3]);

final guysie = pal('spectra6-guysie', [
  ('black', [33, 23, 36], [0, 0, 0]),
  ('white', [143, 154, 152], [255, 255, 255]),
  ('green', [34, 78, 63], [0, 255, 0]),
  ('blue', [8, 71, 127], [0, 0, 255]),
  ('red', [106, 23, 18], [255, 0, 0]),
  ('yellow', [158, 152, 18], [255, 255, 0]),
]);
final ours = pal('spectra6-presets', [
  ('black', [0x1F, 0x22, 0x26], [0, 0, 0]),
  ('white', [0xB9, 0xC7, 0xC9], [255, 255, 255]),
  ('blue', [0x23, 0x3F, 0x8E], [0, 0, 255]),
  ('green', [0x35, 0x56, 0x3A], [0, 255, 0]),
  ('red', [0x62, 0x20, 0x1E], [255, 0, 0]),
  ('yellow', [0xC1, 0xBB, 0x1E], [255, 255, 0]),
]);

typedef Method = Uint8List Function(Uint8List rgba, int w, int h, Palette p);

const mr = OdSettings(
  saturation: 1,
  strength: 0,
  highlightCompress: 1,
  errorSpace: ColorSpace.linear,
  rangeMapping: RangeMapping.mediaRelative,
);

final mrn = mr.copyWith(rangeMapping: RangeMapping.mediaRelativeNeutral);

final methods = <String, Method>{
  'od Auto-tune': (rgba, w, h, p) => runPipeline(rgba, w, h, p, autoTune(rgba, w, h, p).settings),
  'media-relative + linear ED': (rgba, w, h, p) => runPipeline(rgba, w, h, p, mr),
  'MR FS tuned (ΔE)': (rgba, w, h, p) => runPipeline(rgba, w, h, p, fidelityTune(rgba, w, h, p, mr)),
  'MR neutral black': (rgba, w, h, p) => runPipeline(rgba, w, h, p, mrn),
  'MR neutral black, tuned': (rgba, w, h, p) => runPipeline(rgba, w, h, p, fidelityTune(rgba, w, h, p, mrn)),
};

/// Coordinate search on a half-size copy for the settings with the best fidelity
/// score: Auto-tune's idea (iterate the real pipeline against the source) with the
/// fidelity score as the objective.
OdSettings fidelityTune(Uint8List rgba, int w, int h, Palette p, OdSettings base, {double ssimWeight = 0}) {
  final hw = w ~/ 2, hh = h ~/ 2;
  final small = cropResize(rgba, w, h, CropRect(0, 0, w.toDouble(), h.toDouble()), hw, hh);
  final fid = Fidelity(small, hw, hh, p, sigma: 0.75);
  double f(OdSettings s) {
    final (de, ss) = fid.measure(runPipeline(small, hw, hh, p, s));
    return de + ssimWeight * (1 - ss) * 100;
  }
  var best = base;
  var bestScore = f(base);
  final steps = <(String, List<double>, OdSettings Function(OdSettings, double))>[
    ('exposure', [0.9, 0.95, 1.05, 1.1, 1.2], (s, v) => s.copyWith(exposure: v)),
    ('saturation', [0.9, 1.1, 1.2, 1.35], (s, v) => s.copyWith(saturation: v)),
    ('scurve', [0.2, 0.4, 0.6], (s, v) => s.copyWith(strength: v, highlightCompress: 1.5)),
    ('shadows', [0.1, 0.2, 0.3], (s, v) => s.copyWith(shadowBoost: v, strength: s.strength == 0 ? 1 : s.strength, highlightCompress: s.strength == 0 ? 1 : s.highlightCompress)),
  ];
  for (var round = 0; round < 2; round++) {
    for (final (_, values, apply) in steps) {
      for (final v in values) {
        final c = apply(best, v);
        final sc = f(c);
        if (sc < bestScore - 0.01) {
          bestScore = sc;
          best = c;
        }
      }
    }
  }
  return best;
}

/// What the eye sees after adapting to the panel's white: palette colours scaled by
/// the white (per channel, linear), lightly blurred.
img.Image adaptedView(Uint8List idx, Palette p) {
  final white = p.colors[p.names.indexOf('white')];
  final wl = [for (final c in white) srgbToLinear(c)];
  final lin = [for (final c in p.colors) [for (var k = 0; k < 3; k++) srgbToLinear(c[k]) / wl[k]]];
  final im = img.Image(width: 800, height: 480);
  for (var y = 0; y < 480; y++) {
    for (var x = 0; x < 800; x++) {
      final acc = [0.0, 0.0, 0.0];
      var n = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = (x + dx).clamp(0, 799), yy = (y + dy).clamp(0, 479);
          final c = lin[idx[yy * 800 + xx]];
          final wgt = (dx == 0 ? 2 : 1) * (dy == 0 ? 2 : 1);
          for (var k = 0; k < 3; k++) {
            acc[k] += c[k] * wgt;
          }
          n += wgt;
        }
      }
      im.setPixelRgb(x, y, linearToSrgb(acc[0] / n), linearToSrgb(acc[1] / n), linearToSrgb(acc[2] / n));
    }
  }
  return im;
}

void main() {
  final dir = Platform.environment['PHOTOS'];
  if (dir == null) {
    test('fidelity bench', () {}, skip: 'Set PHOTOS to a directory of photos');
    return;
  }
  test('fidelity bench', () {
    final files = Directory(dir).listSync().whereType<File>().where((f) => RegExp(r'\.(png|jpe?g)$').hasMatch(f.path)).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final out = Platform.environment['OUT'];
    for (final p in [guysie, ours]) {
      final totals = <String, double>{}, totals3 = <String, double>{}, ms = <String, int>{}, ssim = <String, double>{};
      for (final f in files) {
        final src = img.decodeImage(f.readAsBytesSync())!.convert(numChannels: 4);
        final rgba = cropResize(src.getBytes(order: img.ChannelOrder.rgba), src.width, src.height,
            CropRect.center(src.width, src.height, 800 / 480), 800, 480);
        final fid = Fidelity(rgba, 800, 480, p), fid3 = Fidelity(rgba, 800, 480, p, sigma: 3);
        for (final m in methods.entries) {
          final sw = Stopwatch()..start();
          final idx = m.value(rgba, 800, 480, p);
          ms[m.key] = (ms[m.key] ?? 0) + sw.elapsedMilliseconds;
          final (de, ss) = fid.measure(idx);
          totals[m.key] = (totals[m.key] ?? 0) + de;
          ssim[m.key] = (ssim[m.key] ?? 0) + ss;
          totals3[m.key] = (totals3[m.key] ?? 0) + fid3.score(idx);
          if (out != null) {
            final im = adaptedView(idx, p);
            final name = f.uri.pathSegments.last.split('.').first;
            File('$out/${p.id}/${name}_${m.key.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(img.encodePng(im));
            File('$out/${p.id}/${name}__source.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(img.encodePng(img.Image.fromBytes(width: 800, height: 480, bytes: rgba.buffer, numChannels: 4)));
          }
        }
      }
      final n = files.length;
      // ignore: avoid_print
      print('\n== ${p.id}: mean ΔE_OK×100 vs source (σ 1.5 / σ 3), SSIM(L), ${files.length} photos ==');
      for (final k in methods.keys) {
        // ignore: avoid_print
        print('  ${(totals[k]! / n).toStringAsFixed(2).padLeft(6)}  ${(totals3[k]! / n).toStringAsFixed(2).padLeft(6)}  '
            '${(ssim[k]! / n).toStringAsFixed(3)}  '
            '${(ms[k]! ~/ n).toString().padLeft(6)} ms  $k');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
