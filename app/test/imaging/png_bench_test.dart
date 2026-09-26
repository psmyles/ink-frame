// Compression benchmark on real photos (not part of the normal run):
//   PHOTOS=<dir of .png/.jpg> flutter test test/imaging/png_bench_test.dart
// For each photo: centre-crop and resize to 800×480, dither (Spectra 6), then encode
// every candidate and print sizes relative to the default candidate list.
@Tags(['bench'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ink_frame/imaging/dither.dart';
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/imaging/png_encoder.dart';
import 'package:ink_frame/imaging/resize.dart';

final spectra6 = Palette(
  id: 'spectra6',
  colors: [for (final h in ['#1F2226', '#B9C7C9', '#233F8E', '#35563A', '#62201E', '#C1BB1E']) Palette.hexToRgb(h)],
  deviceColors: [for (final h in ['#000000', '#ffffff', '#0000ff', '#00ff00', '#ff0000', '#ffff00']) Palette.hexToRgb(h)],
);

void main() {
  final dir = Platform.environment['PHOTOS'];
  if (dir == null) {
    test('png bench', () {}, skip: 'Set PHOTOS to a directory of photos');
    return;
  }

  test('png bench', () {
    final files = Directory(dir).listSync().whereType<File>().where((f) => RegExp(r'\.(png|jpe?g)$').hasMatch(f.path)).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final all = <PngCandidate>[
      for (final order in PaletteOrder.values)
        for (final depth8 in [false, true])
          for (final filter in RowFilter.values)
            for (final s in [ZLibOption.strategyDefault, ZLibOption.strategyFiltered, ZLibOption.strategyRle])
              PngCandidate(order, depth8, filter, s),
    ];
    const modes = {
      'fs': DitherOptions(),
      'atkinson': DitherOptions(kernel: 'atkinson'),
      'ordered4': DitherOptions(mode: DitherMode.ordered),
    };

    for (final mode in modes.entries) {
      final totals = <String, int>{};
      var rgb24 = 0, best = 0, defaultSet = 0, encodeMs = 0;
      final wins = <String, int>{};
      for (final f in files) {
        final src = img.decodeImage(f.readAsBytesSync())!.convert(numChannels: 4);
        final rgba = src.getBytes(order: img.ChannelOrder.rgba);
        final crop = CropRect.center(src.width, src.height, 800 / 480);
        final small = cropResize(rgba, src.width, src.height, crop, 800, 480);
        final indices = dither(small, 800, 480, spectra6, mode.value);

        // What ink-frame-lab exported: a 24-bit RGB PNG of the device colours.
        final dev = img.Image(width: 800, height: 480);
        for (var i = 0; i < indices.length; i++) {
          final c = spectra6.deviceColors[indices[i]];
          dev.setPixelRgb(i % 800, i ~/ 800, c[0], c[1], c[2]);
        }
        rgb24 += img.encodePng(dev, level: 6).length;

        var bestHere = 1 << 30;
        String? bestName;
        for (final c in all) {
          final n = PngEncoder.encodeWith(indices, 800, 480, spectra6.deviceColors, c).bytes.length;
          totals['$c'] = (totals['$c'] ?? 0) + n;
          if (n < bestHere) {
            bestHere = n;
            bestName = '$c';
          }
        }
        best += bestHere;
        wins[bestName!] = (wins[bestName] ?? 0) + 1;
        final sw = Stopwatch()..start();
        final chosen = PngEncoder.encode(indices, 800, 480, spectra6.deviceColors).bytes;
        encodeMs += sw.elapsedMilliseconds;
        defaultSet += chosen.length;
        final out = Platform.environment['OUT'];
        if (out != null) {
          File('$out/${mode.key}_${f.uri.pathSegments.last.split('.').first}.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(chosen);
        }
      }
      final n = files.length;
      String kb(int total) => '${(total / n / 1024).toStringAsFixed(1)} KB';
      // ignore: avoid_print
      print('\n== ${mode.key}: $n photos, average per image ==\n'
          '  24-bit RGB PNG (ink-frame-lab): ${kb(rgb24)}\n'
          '  PngEncoder.encode (zopfli):     ${kb(defaultSet)}  (${encodeMs ~/ n} ms per image)\n'
          '  best zlib-9 candidate per photo: ${kb(best)}\n'
          '  per-photo winners: $wins');
      final sorted = totals.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
      for (final e in sorted.take(4)) {
        // ignore: avoid_print
        print('  ${kb(e.value).padLeft(9)}  ${e.key}');
      }
      // ignore: avoid_print
      print('  … worst: ${kb(sorted.last.value)}  ${sorted.last.key}');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
