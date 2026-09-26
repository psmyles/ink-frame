import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ink_frame/imaging/dither.dart';
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/imaging/png_encoder.dart';
import 'package:ink_frame/imaging/zopfli.dart';

final spectra6 = Palette(
  id: 'spectra6',
  colors: [for (final h in ['#1F2226', '#B9C7C9', '#233F8E', '#35563A', '#62201E', '#C1BB1E']) Palette.hexToRgb(h)],
  deviceColors: [for (final h in ['#000000', '#ffffff', '#0000ff', '#00ff00', '#ff0000', '#ffff00']) Palette.hexToRgb(h)],
);

/// A photo-like dithered image: smooth waves + noise, error-diffused.
Uint8List ditheredSample(int w, int h, {int seed = 1}) {
  final r = math.Random(seed);
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      rgba[i] = (128 + 100 * math.sin(x / 23) + r.nextInt(30)).clamp(0, 255).toInt();
      rgba[i + 1] = (128 + 100 * math.cos(y / 17) + r.nextInt(30)).clamp(0, 255).toInt();
      rgba[i + 2] = (128 + 80 * math.sin((x + y) / 31)).clamp(0, 255).toInt();
      rgba[i + 3] = 255;
    }
  }
  return errorDiffusion(rgba, w, h, spectra6.colors, 'floydSteinberg', true);
}

/// Decodes with package:image and maps pixels back to palette indices.
List<int> decodeToIndices(Uint8List png, List<List<int>> palette) {
  final im = img.decodePng(png)!;
  final out = <int>[];
  for (final p in im) {
    final k = palette.indexWhere((c) => c[0] == p.r && c[1] == p.g && c[2] == p.b);
    expect(k, greaterThanOrEqualTo(0));
    out.add(k);
  }
  return out;
}

void main() {
  group('zopfli', () {
    Uint8List inflate(Uint8List z) => Uint8List.fromList(ZLibCodec().decode(z));

    test('round trips through zlib', () {
      final r = math.Random(3);
      final cases = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList([42]),
        Uint8List.fromList(List.filled(100000, 7)), // one long run
        Uint8List.fromList(List.generate(70000, (_) => r.nextInt(256))), // incompressible
        Uint8List.fromList(List.generate(50000, (i) => (i * 7 % 13) + r.nextInt(3))), // patterned
        Uint8List.fromList(('abcabcabcabd' * 5000).codeUnits),
      ];
      for (final c in cases) {
        final z = Zopfli.zlib(c, iterations: 3);
        expect(inflate(z), c, reason: 'length ${c.length}');
      }
    });

    test('smaller than zlib level 9 on dithered pixels', () {
      final idx = ditheredSample(400, 240);
      final packed = Uint8List(idx.length ~/ 2);
      for (var i = 0; i < packed.length; i++) {
        packed[i] = (idx[2 * i] << 4) | idx[2 * i + 1];
      }
      final z9 = ZLibCodec(level: 9).encode(packed).length;
      final zz = Zopfli.zlib(packed, iterations: 5);
      expect(inflate(zz), packed);
      expect(zz.length, lessThan(z9));
      // ignore: avoid_print
      print('zlib 9: $z9 B, zopfli: ${zz.length} B (${(100 * (1 - zz.length / z9)).toStringAsFixed(1)} % smaller)');
    });
  });

  group('png', () {
    test('decodes back to the same pixels, palette of device colours, 4-bit', () {
      final idx = ditheredSample(203, 97); // odd width: partial last byte
      final e = PngEncoder.encode(idx, 203, 97, spectra6.deviceColors, zopfli: 3);
      expect(e.bitDepth, 4);
      expect(decodeToIndices(e.bytes, spectra6.deviceColors), idx);
      final im = img.decodePng(e.bytes)!;
      expect((im.width, im.height), (203, 97));
    });

    test('every candidate decodes correctly', () {
      final idx = ditheredSample(64, 33);
      for (final order in PaletteOrder.values) {
        for (final depth8 in [false, true]) {
          for (final f in RowFilter.values) {
            final e = PngEncoder.encodeWith(idx, 64, 33, spectra6.deviceColors, PngCandidate(order, depth8, f, ZLibOption.strategyDefault));
            expect(decodeToIndices(e.bytes, spectra6.deviceColors), idx, reason: '$order $depth8 $f');
          }
        }
      }
    });

    test('fewer colours use fewer bits', () {
      for (final (colors, depth) in [(2, 1), (3, 2), (4, 2), (5, 4)]) {
        final idx = Uint8List.fromList(List.generate(50 * 20, (i) => (i * 7 + i ~/ 50) % colors));
        final e = PngEncoder.encode(idx, 50, 20, spectra6.deviceColors, zopfli: 2);
        expect(e.bitDepth, depth, reason: '$colors colours');
        expect(e.colors, colors);
        expect(decodeToIndices(e.bytes, spectra6.deviceColors), idx);
      }
      // Two colours that aren't the first two still get 1 bit.
      final idx = Uint8List.fromList(List.generate(200, (i) => i.isEven ? 3 : 5));
      final e = PngEncoder.encode(idx, 20, 10, spectra6.deviceColors, zopfli: 2);
      expect(e.bitDepth, 1);
      expect(decodeToIndices(e.bytes, spectra6.deviceColors), idx);
    });

    test('only IHDR, PLTE, IDAT and IEND', () {
      final e = PngEncoder.encode(ditheredSample(40, 20), 40, 20, spectra6.deviceColors, zopfli: 1);
      final types = <String>[];
      final bd = ByteData.sublistView(e.bytes);
      for (var i = 8; i < e.bytes.length;) {
        final n = bd.getUint32(i);
        types.add(String.fromCharCodes(e.bytes.sublist(i + 4, i + 8)));
        i += 12 + n;
      }
      expect(types, ['IHDR', 'PLTE', 'IDAT', 'IEND']);
    });
  });
}
