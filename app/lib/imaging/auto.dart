// "Automatic": the default processing (app-flow §3.3.1, PLAN.md §8.3).
//
// Built from opendithering's approach (tune per photo by running the real pipeline
// against the source) with changes that measured closer to the original on real
// photos (app/test/imaging/fidelity_bench_test.dart):
// - the photo's black and white map to the panel's, per channel in linear light
//   (media-relative), instead of scaling luminance only;
// - error is diffused in linear light, the way the eye blends dots;
// - the tuner minimises the fidelity score (lib/imaging/fidelity.dart) directly,
//   instead of matching mean chroma.

import 'dart:typed_data';

import 'fidelity.dart';
import 'od_pipeline.dart';
import 'palette.dart';
import 'resize.dart';

/// The untuned starting point: faithful mapping, no creative adjustments.
const OdSettings faithful = OdSettings(
  saturation: 1,
  strength: 0,
  highlightCompress: 1,
  errorSpace: ColorSpace.linear,
  distSpace: ColorSpace.oklab,
  rangeMapping: RangeMapping.mediaRelativeNeutral,
);

/// Per-photo settings that make the frame's picture closest to [rgba] (already at
/// the display size). Searches exposure, colour, contrast and shadow lift on a
/// half-size copy (~0.7 s per photo on a desktop).
OdSettings autoSettings(Uint8List rgba, int w, int h, Palette palette, {OdSettings base = faithful}) {
  final hw = w ~/ 2, hh = h ~/ 2;
  final small = cropResize(rgba, w, h, CropRect(0, 0, w.toDouble(), h.toDouble()), hw, hh);
  final fid = Fidelity(small, hw, hh, palette, sigma: 0.75);
  double score(OdSettings s) => fid.score(runPipeline(small, hw, hh, palette, s));

  var best = base;
  var bestScore = score(base);
  final steps = <(List<double>, OdSettings Function(OdSettings, double))>[
    ([0.9, 0.95, 1.05, 1.1, 1.2], (s, v) => s.copyWith(exposure: v)),
    ([0.9, 1.1, 1.2, 1.35], (s, v) => s.copyWith(saturation: v)),
    ([0.2, 0.4, 0.6], (s, v) => s.copyWith(strength: v, highlightCompress: 1.5)),
    (
      [0.1, 0.2, 0.3],
      (s, v) => s.strength == 0 ? s.copyWith(shadowBoost: v, strength: 1, highlightCompress: 1) : s.copyWith(shadowBoost: v),
    ),
  ];
  for (var round = 0; round < 2; round++) {
    for (final (values, apply) in steps) {
      for (final v in values) {
        final c = apply(best, v);
        final sc = score(c);
        if (sc < bestScore - 0.01) {
          bestScore = sc;
          best = c;
        }
      }
    }
  }
  return best;
}
