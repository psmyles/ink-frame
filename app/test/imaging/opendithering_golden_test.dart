// The Dart port must match reference/opendithering (shared/test-vectors/
// opendithering.json, from tools/golden/gen-opendithering.mjs).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/imaging/autotune.dart';
import 'package:ink_frame/imaging/od_pipeline.dart';
import 'package:ink_frame/imaging/palette.dart';

void main() {
  final v = jsonDecode(File('../shared/test-vectors/opendithering.json').readAsStringSync()) as Map<String, dynamic>;
  final palettes = {
    for (final e in (v['palettes'] as Map<String, dynamic>).entries)
      e.key: Palette(
        id: e.key,
        names: [for (final c in e.value as List) c['name'] as String],
        colors: [for (final c in e.value as List) (c['measured'] as List).cast<int>()],
        deviceColors: [for (final c in e.value as List) (c['ideal'] as List).cast<int>()],
      ),
  };
  final inputs = {
    for (final i in (v['inputs'] as List).cast<Map<String, dynamic>>())
      i['name'] as String: (i['width'] as int, i['height'] as int, base64Decode(i['rgba'] as String)),
  };

  int mismatches(List<int> a, List<int> b) {
    var n = 0;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) n++;
    }
    return n;
  }

  group('pipeline', () {
    for (final c in (v['pipeline'] as List).cast<Map<String, dynamic>>()) {
      test('${c['input']} ${c['name']}', () {
        final (w, h, rgba) = inputs[c['input']]!;
        final got = runPipeline(rgba, w, h, palettes[c['palette']]!, OdSettings.fromJson(c['settings'] as Map<String, dynamic>));
        expect(mismatches(got, base64Decode(c['indices'] as String)), 0);
      });
    }
  });

  group('auto-tune', () {
    for (final c in (v['autotune'] as List).cast<Map<String, dynamic>>()) {
      test('${c['input']} ${c['palette']}', () {
        final (w, h, rgba) = inputs[c['input']]!;
        final r = autoTune(rgba, w, h, palettes[c['palette']]!);
        void same(OdSettings got, Map<String, dynamic> want, String step) {
          final w = OdSettings.fromJson(want);
          for (final (name, a, b) in [
            ('exposure', got.exposure, w.exposure),
            ('strength', got.strength, w.strength),
            ('shadowBoost', got.shadowBoost, w.shadowBoost),
            ('highlightCompress', got.highlightCompress, w.highlightCompress),
            ('saturation', got.saturation, w.saturation),
            ('redGain', got.redGain, w.redGain),
            ('greenGain', got.greenGain, w.greenGain),
            ('blueGain', got.blueGain, w.blueGain),
          ]) {
            expect(a, closeTo(b, 1e-9), reason: '$step $name');
          }
          for (var k = 0; k < 6; k++) {
            expect(got.hueSatBands[k], closeTo(w.hueSatBands[k], 1e-9), reason: '$step band $k');
          }
        }

        same(r.afterExpose, c['afterExpose'] as Map<String, dynamic>, 'expose');
        same(r.afterColor, c['afterColor'] as Map<String, dynamic>, 'color');
        same(r.settings, c['final'] as Map<String, dynamic>, 'hue');
        expect(r.colorIterations, c['colorIterations']);
        expect(r.hueIterations, c['hueIterations']);
        final got = runPipeline(rgba, w, h, palettes[c['palette']]!, r.settings);
        expect(mismatches(got, base64Decode(c['indices'] as String)), 0);
      });
    }
  });
}
