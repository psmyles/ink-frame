// The Dart port must match reference/ink-frame-lab/js/dithering.js exactly
// (shared/test-vectors/dither.json, from tools/golden/gen-vectors.mjs).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/imaging/dither.dart';

void main() {
  final vectors = jsonDecode(File('../shared/test-vectors/dither.json').readAsStringSync()) as Map<String, dynamic>;
  final palettes = {
    for (final e in (vectors['palettes'] as Map<String, dynamic>).entries)
      e.key: [for (final c in e.value as List) (c as List).cast<int>()],
  };
  final inputs = {
    for (final i in (vectors['inputs'] as List).cast<Map<String, dynamic>>())
      i['name'] as String: (i['width'] as int, i['height'] as int, base64Decode(i['rgba'] as String)),
  };

  for (final c in (vectors['cases'] as List).cast<Map<String, dynamic>>()) {
    final name = [c['input'], c['palette'], c['mode'], c['kernel'], c['serpentine'], c['orderedW'], c['orderedH']]
        .where((v) => v != null)
        .join(' ');
    test(name, () {
      final (w, h, rgba) = inputs[c['input']]!;
      final pal = palettes[c['palette']]!;
      final got = switch (c['mode']) {
        'quantization' => quantize(rgba, w, h, pal),
        'errorDiffusion' => errorDiffusion(rgba, w, h, pal, c['kernel'] as String, c['serpentine'] as bool),
        _ => ordered(rgba, w, h, pal, c['orderedW'] as int, c['orderedH'] as int),
      };
      final want = base64Decode(c['indices'] as String);
      final first = List.generate(want.length, (i) => i).firstWhere((i) => got[i] != want[i], orElse: () => -1);
      expect(first, -1, reason: first < 0 ? null : 'first mismatch at pixel $first (x ${first % w}, y ${first ~/ w})');
    });
  }

  test('random dither: noise averages out, strength 40', () {
    final pal = palettes['spectra6']!;
    // A mid grey between palette colours: with noise, several colours appear;
    // without it, only the nearest one.
    final rgba = Uint8List(200 * 200 * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba.setAll(i, [110, 118, 125, 255]);
    }
    final plain = quantize(rgba, 200, 200, pal).toSet();
    expect(plain.length, 1);
    for (final type in RandomType.values) {
      final rng = math.Random(7);
      final out = randomDither(rgba, 200, 200, pal, type, rng.nextDouble);
      final counts = <int, int>{};
      for (final v in out) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
      expect(counts.length, greaterThan(1), reason: '$type adds noise');
      // Noise is ±20: the nearest colour still dominates.
      expect(counts[plain.single]! / out.length, greaterThan(0.4), reason: '$type');
      // Deterministic with the same generator.
      expect(randomDither(rgba, 200, 200, pal, type, math.Random(7).nextDouble), out);
    }
    // Zero noise (random() == 0.5 always) is plain quantization.
    expect(randomDither(rgba, 200, 200, pal, RandomType.rgb, () => 0.5).toSet(), plain);
  });
}
