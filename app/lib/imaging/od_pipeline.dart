// opendithering's processing pipeline and colour-space-aware error diffusion,
// ported from reference/opendithering/src/processing/pipeline.ts and
// src/dithering/error-diffusion.ts (MIT). Output is palette indices.

import 'dart:math' as math;
import 'dart:typed_data';

import 'color_space.dart';
import 'dither.dart' show Kernel;
import 'palette.dart';
import 'tone.dart';

/// [linear] (linear-light RGB, 0–1) is an Ink Frame addition: error diffused the
/// way the eye averages light. The others are opendithering's.
enum ColorSpace { rgb, cielab, oklab, oklabChroma, linear }

enum ToneMode { contrast, scurve }

/// How the source is fitted into the panel's black–white range.
enum RangeMapping {
  /// opendithering's compressDynamicRange: scales luminance only.
  luminance,

  /// Ink Frame: per channel in linear light, source black/white → the panel's
  /// black/white (media-relative, as print colour management does). Neutrals map to
  /// the panel's own neutrals, so whites don't pick up a cast from the panel's tint.
  mediaRelative,

  /// As [mediaRelative], but black maps to the darkest *neutral* the panel can mix
  /// (its black plus a few dots of other inks to cancel the black's tint), so
  /// shadows stay grey instead of taking on the tint of the panel's black.
  mediaRelativeNeutral,
}

/// `ProcessingSettings` (types.ts). Field names and ranges as there.
class OdSettings {
  const OdSettings({
    this.exposure = 1.0,
    this.saturation = 1.3,
    this.compressDynamicRange = true,
    this.toneMode = ToneMode.scurve,
    this.contrast = 1.0,
    this.strength = 0.9,
    this.shadowBoost = 0.0,
    this.highlightCompress = 1.5,
    this.midpoint = 0.5,
    this.errorSpace = ColorSpace.oklab,
    this.distSpace = ColorSpace.oklab,
    this.ditherStrength = 1.0,
    this.localVarianceDetection = false,
    this.redGain = 1.0,
    this.greenGain = 1.0,
    this.blueGain = 1.0,
    this.algorithm = 'floyd-steinberg',
    this.serpentine = true,
    this.clarity = 0.0,
    this.clarityRadius = 2,
    this.hueSatBands = const [1, 1, 1, 1, 1, 1],
    this.rangeMapping = RangeMapping.luminance,
  });

  final double exposure, saturation;
  final bool compressDynamicRange;
  final ToneMode toneMode;
  final double contrast, strength, shadowBoost, highlightCompress, midpoint;
  final ColorSpace errorSpace, distSpace;
  final double ditherStrength;
  final bool localVarianceDetection;
  final double redGain, greenGain, blueGain;

  /// floyd-steinberg, atkinson, jarvis, stucki, burkes, sierra.
  final String algorithm;
  final bool serpentine;
  final double clarity;
  final int clarityRadius;

  /// Saturation per hue: red, yellow, green, cyan, blue, magenta.
  final List<double> hueSatBands;

  /// Used when [compressDynamicRange] is on.
  final RangeMapping rangeMapping;

  /// opendithering's Balanced preset (the starting point of Auto-tune).
  static const balanced = OdSettings();

  OdSettings copyWith({
    double? exposure,
    double? saturation,
    bool? compressDynamicRange,
    ToneMode? toneMode,
    double? contrast,
    double? strength,
    double? shadowBoost,
    double? highlightCompress,
    double? midpoint,
    ColorSpace? errorSpace,
    ColorSpace? distSpace,
    double? ditherStrength,
    bool? localVarianceDetection,
    double? redGain,
    double? greenGain,
    double? blueGain,
    String? algorithm,
    bool? serpentine,
    double? clarity,
    int? clarityRadius,
    List<double>? hueSatBands,
    RangeMapping? rangeMapping,
  }) =>
      OdSettings(
        exposure: exposure ?? this.exposure,
        saturation: saturation ?? this.saturation,
        compressDynamicRange: compressDynamicRange ?? this.compressDynamicRange,
        toneMode: toneMode ?? this.toneMode,
        contrast: contrast ?? this.contrast,
        strength: strength ?? this.strength,
        shadowBoost: shadowBoost ?? this.shadowBoost,
        highlightCompress: highlightCompress ?? this.highlightCompress,
        midpoint: midpoint ?? this.midpoint,
        errorSpace: errorSpace ?? this.errorSpace,
        distSpace: distSpace ?? this.distSpace,
        ditherStrength: ditherStrength ?? this.ditherStrength,
        localVarianceDetection: localVarianceDetection ?? this.localVarianceDetection,
        redGain: redGain ?? this.redGain,
        greenGain: greenGain ?? this.greenGain,
        blueGain: blueGain ?? this.blueGain,
        algorithm: algorithm ?? this.algorithm,
        serpentine: serpentine ?? this.serpentine,
        clarity: clarity ?? this.clarity,
        clarityRadius: clarityRadius ?? this.clarityRadius,
        hueSatBands: hueSatBands ?? this.hueSatBands,
        rangeMapping: rangeMapping ?? this.rangeMapping,
      );

  /// From opendithering's JSON field names (test vectors).
  factory OdSettings.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num).toDouble();
    ColorSpace cs(String k) => switch (j[k]) {
          'rgb' => ColorSpace.rgb,
          'cielab' => ColorSpace.cielab,
          'oklab' => ColorSpace.oklab,
          _ => ColorSpace.oklabChroma,
        };
    return OdSettings(
      exposure: d('exposure'),
      saturation: d('saturation'),
      compressDynamicRange: j['compressDynamicRange'] as bool,
      toneMode: j['toneMode'] == 'contrast' ? ToneMode.contrast : ToneMode.scurve,
      contrast: d('contrast'),
      strength: d('strength'),
      shadowBoost: d('shadowBoost'),
      highlightCompress: d('highlightCompress'),
      midpoint: d('midpoint'),
      errorSpace: cs('errorSpace'),
      distSpace: cs('distSpace'),
      ditherStrength: d('ditherStrength'),
      localVarianceDetection: j['localVarianceDetection'] as bool,
      redGain: d('redGain'),
      greenGain: d('greenGain'),
      blueGain: d('blueGain'),
      algorithm: j['ditherAlgorithm'] as String,
      serpentine: j['serpentine'] as bool,
      clarity: d('clarity'),
      clarityRadius: (j['clarityRadius'] as num).toInt(),
      hueSatBands: [for (final v in j['hueSatBands'] as List) (v as num).toDouble()],
    );
  }
}

const _kernels = {
  'floyd-steinberg': 'floydSteinberg',
  'atkinson': 'atkinson',
  'jarvis': 'jarvis',
  'stucki': 'stucki',
  'burkes': 'burkes',
  'sierra': 'sierra3',
};

/// Black and white entries by name, else first and last (compressDynamicRange).
(List<int>, List<int>) blackWhite(Palette p) {
  final names = p.names;
  final bi = names.indexOf('black'), wi = names.indexOf('white');
  return (p.colors[bi >= 0 ? bi : 0], p.colors[wi >= 0 ? wi : p.length - 1]);
}

/// Adjusts [rgba] in place: steps 1.5–6 of runPipeline.
void adjust(Uint8List rgba, int width, int height, Palette palette, OdSettings s) {
  if (s.clarity != 0) applyClarity(rgba, width, height, s.clarity, s.clarityRadius);
  if (s.compressDynamicRange) {
    final (black, white) = blackWhite(palette);
    if (s.rangeMapping == RangeMapping.mediaRelative) {
      mapToMediaRange(rgba, black, white);
    } else if (s.rangeMapping == RangeMapping.mediaRelativeNeutral) {
      mapToMediaRangeLinear(rgba, neutralBlack(palette, white), white);
    } else {
      compressDynamicRange(rgba, black, white);
    }
  }
  if (s.toneMode == ToneMode.contrast) {
    applyContrastTone(rgba, s.contrast);
  } else {
    applySCurve(rgba, s.strength, s.shadowBoost, s.highlightCompress, s.midpoint);
  }
  applySaturation(rgba, s.saturation);
  if (s.hueSatBands.any((v) => v != 1)) applyHueSatBands(rgba, s.hueSatBands);
  applyExposure(rgba, s.exposure);
  applyChannelGains(rgba, s.redGain, s.greenGain, s.blueGain);
}

/// runPipeline on an image already at the display size. Doesn't modify [rgba].
Uint8List runPipeline(Uint8List rgba, int width, int height, Palette palette, OdSettings s) {
  final work = Uint8List.fromList(rgba);
  adjust(work, width, height, palette, s);
  return errorDiffuse(work, width, height, palette, s);
}

void _toSpace(num r, num g, num b, ColorSpace space, Float64List out) {
  switch (space) {
    case ColorSpace.cielab:
      rgbToLabInto(r, g, b, out);
    case ColorSpace.oklab || ColorSpace.oklabChroma:
      rgbToOklabInto(r, g, b, out);
    case ColorSpace.rgb:
      out[0] = r.toDouble();
      out[1] = g.toDouble();
      out[2] = b.toDouble();
    case ColorSpace.linear:
      out[0] = srgbToLinear(r);
      out[1] = srgbToLinear(g);
      out[2] = srgbToLinear(b);
  }
}

Float32List buildVarianceMap(Uint8List data, int w, int h) {
  final map = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      double sum = 0, sumSq = 0;
      var count = 0;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          final nx = math.min(w - 1, math.max(0, x + dx)), ny = math.min(h - 1, math.max(0, y + dy));
          final i = (ny * w + nx) * 4;
          final lum = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
          sum += lum;
          sumSq += lum * lum;
          count++;
        }
      }
      final mean = sum / count;
      map[y * w + x] = math.min(1, math.sqrt(math.max(0, sumSq / count - mean * mean)) / 15);
    }
  }
  return map;
}

/// errorDiffuse (error-diffusion.ts): error kept in [OdSettings.errorSpace],
/// nearest colour chosen in [OdSettings.distSpace].
Uint8List errorDiffuse(Uint8List src, int w, int h, Palette palette, OdSettings s) {
  final errSpace = s.errorSpace, distSpace = s.distSpace;
  final kernel = Kernel.all[_kernels[s.algorithm] ?? 'floydSteinberg']!;
  final n = palette.length;
  final tmp = Float64List(3);
  final errPal = Float64List(n * 3), distPal = Float64List(n * 3);
  for (var i = 0; i < n; i++) {
    final c = palette.colors[i];
    _toSpace(c[0], c[1], c[2], errSpace, tmp);
    errPal.setAll(i * 3, tmp);
    _toSpace(c[0], c[1], c[2], distSpace, tmp);
    distPal.setAll(i * 3, tmp);
  }

  final buf = Float32List(w * h * 3);
  for (var i = 0; i < w * h; i++) {
    _toSpace(src[i * 4], src[i * 4 + 1], src[i * 4 + 2], errSpace, tmp);
    buf[i * 3] = tmp[0];
    buf[i * 3 + 1] = tmp[1];
    buf[i * 3 + 2] = tmp[2];
  }
  final varMap = s.localVarianceDetection ? buildVarianceMap(src, w, h) : null;
  final out = Uint8List(w * h);
  final weights = kernel.weights;
  final divisor = kernel.divisor;
  final dp = Float64List(3);

  for (var y = 0; y < h; y++) {
    final ltr = !s.serpentine || y % 2 == 0;
    final xStart = ltr ? 0 : w - 1, xEnd = ltr ? w : -1, xStep = ltr ? 1 : -1;
    for (var x = xStart; x != xEnd; x += xStep) {
      final bi = (y * w + x) * 3;
      double e0 = buf[bi], e1 = buf[bi + 1], e2 = buf[bi + 2];
      switch (errSpace) {
        case ColorSpace.rgb:
          e0 = math.min(255, math.max(0, e0));
          e1 = math.min(255, math.max(0, e1));
          e2 = math.min(255, math.max(0, e2));
        case ColorSpace.oklab || ColorSpace.oklabChroma:
          e0 = math.min(1, math.max(0, e0));
          e1 = math.min(0.5, math.max(-0.5, e1));
          e2 = math.min(0.5, math.max(-0.5, e2));
        case ColorSpace.cielab:
          e0 = math.min(100, math.max(0, e0));
          e1 = math.min(128, math.max(-128, e1));
          e2 = math.min(128, math.max(-128, e2));
        case ColorSpace.linear:
          e0 = math.min(1, math.max(0, e0));
          e1 = math.min(1, math.max(0, e1));
          e2 = math.min(1, math.max(0, e2));
      }
      if (errSpace == ColorSpace.linear && distSpace != ColorSpace.linear) {
        if (distSpace == ColorSpace.oklab || distSpace == ColorSpace.oklabChroma) {
          linearToOklabInto(e0, e1, e2, dp);
        } else {
          _toSpace(linearToSrgb(e0), linearToSrgb(e1), linearToSrgb(e2), distSpace, dp);
        }
      } else if (errSpace != distSpace && errSpace == ColorSpace.rgb) {
        _toSpace(e0, e1, e2, distSpace, dp);
      } else {
        dp[0] = e0;
        dp[1] = e1;
        dp[2] = e2;
      }
      // As in the JS, the distance palette is used even when the two perceptual
      // spaces differ (it notes cross-space conversion isn't supported).
            var best = 0;
      var bestDist = double.infinity;
      final chromaBoost = distSpace == ColorSpace.oklabChroma ? 1 + math.sqrt(dp[1] * dp[1] + dp[2] * dp[2]) * 10 : 1.0;
      for (var i = 0; i < n; i++) {
        final d0 = dp[0] - distPal[i * 3], d1 = dp[1] - distPal[i * 3 + 1], d2 = dp[2] - distPal[i * 3 + 2];
        final d = switch (distSpace) {
          ColorSpace.cielab => 2 * d0 * d0 + d1 * d1 + d2 * d2,
          ColorSpace.oklabChroma => d0 * d0 + (d1 * d1 + d2 * d2) * chromaBoost,
          _ => d0 * d0 + d1 * d1 + d2 * d2,
        };
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      out[y * w + x] = best;

      final strength = varMap != null ? s.ditherStrength * varMap[y * w + x] : s.ditherStrength;
      if (strength > 0) {
        final err0 = (e0 - errPal[best * 3]) * strength;
        final err1 = (e1 - errPal[best * 3 + 1]) * strength;
        final err2 = (e2 - errPal[best * 3 + 2]) * strength;
        for (final k in weights) {
          final nx = x + (ltr ? k[0] : -k[0]), ny = y + k[1];
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          final ni = (ny * w + nx) * 3;
          final f = k[2] / divisor;
          buf[ni] += err0 * f;
          buf[ni + 1] += err1 * f;
          buf[ni + 2] += err2 * f;
        }
      }
    }
  }
  return out;
}

final _neutralBlackCache = Expando<List<double>>();

/// The darkest mix of palette colours that looks neutral once the eye adapts to the
/// panel's white, as linear RGB. Searches mixes of black with up to two other inks.
List<double> neutralBlack(Palette p, List<int> white) {
  final cached = _neutralBlackCache[p];
  if (cached != null) return cached;
  final lin = [for (final c in p.colors) [for (var k = 0; k < 3; k++) srgbToLinear(c[k])]];
  final wl = [for (var k = 0; k < 3; k++) srgbToLinear(white[k])];
  final (blackRgb, _) = blackWhite(p);
  final bi = p.colors.indexOf(blackRgb);
  final lab = Float64List(3);
  List<double> mix(Map<int, double> w) {
    final out = [0.0, 0.0, 0.0];
    w.forEach((i, f) {
      for (var k = 0; k < 3; k++) {
        out[k] += lin[i][k] * f;
      }
    });
    return out;
  }

  var best = lin[bi];
  var bestCost = double.infinity;
  const step = 0.01;
  for (var a = 0; a < p.length; a++) {
    for (var b = a; b < p.length; b++) {
      if (a == bi || b == bi) continue;
      for (var fa = 0.0; fa <= 0.3 + 1e-9; fa += step) {
        for (var fb = 0.0; fb <= 0.3 - fa + 1e-9; fb += step) {
          final m = mix({bi: 1 - fa - fb, a: fa, if (b != a) b: fb});
          linearToOklabInto(m[0] / wl[0], m[1] / wl[1], m[2] / wl[2], lab);
          final chroma = math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
          // Lightness, heavily penalising any remaining tint.
          final cost = lab[0] + 4 * chroma;
          if (cost < bestCost) {
            bestCost = cost;
            best = m;
          }
        }
      }
    }
  }
  return _neutralBlackCache[p] = best;
}
