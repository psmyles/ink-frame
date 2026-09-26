import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ink_frame/imaging/png_encoder.dart';
import 'package:ink_frame/imaging/png_palette.dart';

void main() {
  test('recolours PLTE and keeps the PNG valid', () {
    const device = [[0, 0, 0], [255, 255, 255], [255, 0, 0]];
    const calibrated = [[31, 34, 38], [185, 199, 201], [98, 32, 30]];
    final idx = Uint8List.fromList(List.generate(30 * 10, (i) => i % 3));
    final png = PngEncoder.encode(idx, 30, 10, device, zopfli: 0).bytes;
    final out = recolorPng(png, device, calibrated);
    final decoded = img.decodePng(out)!; // CRC is checked by the decoder
    for (var i = 0; i < idx.length; i++) {
      final p = decoded.getPixel(i % 30, i ~/ 30);
      expect([p.r, p.g, p.b], calibrated[idx[i]]);
    }
    expect(out.length, png.length);
  });
}
