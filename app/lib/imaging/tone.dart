// Tone and colour adjustments, ported from
// reference/opendithering/src/processing/tone.ts (MIT). All work in place on RGBA
// bytes with the same rounding as the JS (Uint8ClampedArray stores).

import 'dart:math' as math;
import 'dart:typed_data';

import 'color_space.dart';

int _u8(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

/// Maps luminance into the panel's real [black, white] range.
void compressDynamicRange(Uint8List data, List<int> black, List<int> white) {
  final blackY = rec709Luminance(black[0], black[1], black[2]);
  final whiteY = rec709Luminance(white[0], white[1], white[2]);
  final range = whiteY - blackY;
  for (var i = 0; i < data.length; i += 4) {
    final lr = srgbToLinear(data[i]), lg = srgbToLinear(data[i + 1]), lb = srgbToLinear(data[i + 2]);
    final y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb;
    if (y < 1e-6) continue;
    final scale = (blackY + y * range) / y;
    data[i] = linearToSrgb(lr * scale);
    data[i + 1] = linearToSrgb(lg * scale);
    data[i + 2] = linearToSrgb(lb * scale);
  }
}

/// Per channel in linear light: 0 → the panel's black, 1 → its white.
void mapToMediaRange(Uint8List data, List<int> black, List<int> white) {
  final luts = [
    for (var c = 0; c < 3; c++)
      Uint8List.fromList([
        for (var v = 0; v < 256; v++)
          linearToSrgb(srgbToLinear(black[c]) + srgbToLinear(v) * (srgbToLinear(white[c]) - srgbToLinear(black[c]))),
      ]),
  ];
  for (var i = 0; i < data.length; i += 4) {
    data[i] = luts[0][data[i]];
    data[i + 1] = luts[1][data[i + 1]];
    data[i + 2] = luts[2][data[i + 2]];
  }
}

/// As [mapToMediaRange] with the black point given in linear light.
void mapToMediaRangeLinear(Uint8List data, List<double> blackLinear, List<int> white) {
  final luts = [
    for (var c = 0; c < 3; c++)
      Uint8List.fromList([
        for (var v = 0; v < 256; v++) linearToSrgb(blackLinear[c] + srgbToLinear(v) * (srgbToLinear(white[c]) - blackLinear[c])),
      ]),
  ];
  for (var i = 0; i < data.length; i += 4) {
    data[i] = luts[0][data[i]];
    data[i + 1] = luts[1][data[i + 1]];
    data[i + 2] = luts[2][data[i + 2]];
  }
}

int _contrast(int v, double c) => math.min(255, math.max(0, jsRound((v - 128) * c + 128)));

int _sCurve(int v, double strength, double shadowBoost, double highlightCompress, double midpoint) {
  final t = v / 255;
  final shadow = t < midpoint ? t + shadowBoost * math.pow(1 - t / midpoint, 2) * midpoint : t;
  final highlight = shadow > midpoint
      ? midpoint + math.pow((shadow - midpoint) / (1 - midpoint), highlightCompress) * (1 - midpoint)
      : shadow;
  final result = t * (1 - strength) + highlight * strength;
  return math.min(255, math.max(0, jsRound(result * 255)));
}

void applyContrastTone(Uint8List data, double contrast) {
  final lut = Uint8List.fromList([for (var v = 0; v < 256; v++) _contrast(v, contrast)]);
  for (var i = 0; i < data.length; i += 4) {
    data[i] = lut[data[i]];
    data[i + 1] = lut[data[i + 1]];
    data[i + 2] = lut[data[i + 2]];
  }
}

void applySCurve(Uint8List data, double strength, double shadowBoost, double highlightCompress, double midpoint) {
  final lut = Uint8List.fromList([for (var v = 0; v < 256; v++) _sCurve(v, strength, shadowBoost, highlightCompress, midpoint)]);
  for (var i = 0; i < data.length; i += 4) {
    data[i] = lut[data[i]];
    data[i + 1] = lut[data[i + 1]];
    data[i + 2] = lut[data[i + 2]];
  }
}

// ── HSL ──

/// Returns (h 0–1, s, l) into [out].
void rgbToHsl(int r, int g, int b, Float64List out) {
  final rn = r / 255, gn = g / 255, bn = b / 255;
  final mx = math.max(rn, math.max(gn, bn)), mn = math.min(rn, math.min(gn, bn));
  final l = (mx + mn) / 2;
  if (mx == mn) {
    out[0] = 0;
    out[1] = 0;
    out[2] = l;
    return;
  }
  final d = mx - mn;
  final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
  double h;
  if (mx == rn) {
    h = (gn - bn) / d + (gn < bn ? 6 : 0);
  } else if (mx == gn) {
    h = (bn - rn) / d + 2;
  } else {
    h = (rn - gn) / d + 4;
  }
  out[0] = h / 6;
  out[1] = s;
  out[2] = l;
}

double _hue2rgb(double p, double q, double t) {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1 / 6) return p + (q - p) * 6 * t;
  if (t < 1 / 2) return q;
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
  return p;
}

void _hslToRgbInto(double h, double s, double l, Uint8List data, int i) {
  if (s == 0) {
    final v = _u8(jsRound(l * 255));
    data[i] = v;
    data[i + 1] = v;
    data[i + 2] = v;
    return;
  }
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  data[i] = _u8(jsRound(_hue2rgb(p, q, h + 1 / 3) * 255));
  data[i + 1] = _u8(jsRound(_hue2rgb(p, q, h) * 255));
  data[i + 2] = _u8(jsRound(_hue2rgb(p, q, h - 1 / 3) * 255));
}

void applySaturation(Uint8List data, double saturation) {
  final hsl = Float64List(3);
  for (var i = 0; i < data.length; i += 4) {
    rgbToHsl(data[i], data[i + 1], data[i + 2], hsl);
    _hslToRgbInto(hsl[0], math.min(1, hsl[1] * saturation), hsl[2], data, i);
  }
}

/// Per-hue saturation multipliers [red, yellow, green, cyan, blue, magenta],
/// interpolated between band centres 60° apart.
void applyHueSatBands(Uint8List data, List<double> bands) {
  final hsl = Float64List(3);
  for (var i = 0; i < data.length; i += 4) {
    rgbToHsl(data[i], data[i + 1], data[i + 2], hsl);
    if (hsl[1] == 0) continue;
    final hDeg = hsl[0] * 360;
    final band = (hDeg / 60).floor() % 6, next = (band + 1) % 6;
    final t = (hDeg % 60) / 60;
    final mult = (1 - t) * bands[band] + t * bands[next];
    _hslToRgbInto(hsl[0], math.min(1, hsl[1] * mult), hsl[2], data, i);
  }
}

void applyExposure(Uint8List data, double exposure) => applyChannelGains(data, exposure, exposure, exposure);

void applyChannelGains(Uint8List data, double r, double g, double b) {
  if (r == 1 && g == 1 && b == 1) return;
  final lr = Uint8List.fromList([for (var v = 0; v < 256; v++) math.min(255, jsRound(v * r))]);
  final lg = Uint8List.fromList([for (var v = 0; v < 256; v++) math.min(255, jsRound(v * g))]);
  final lb = Uint8List.fromList([for (var v = 0; v < 256; v++) math.min(255, jsRound(v * b))]);
  for (var i = 0; i < data.length; i += 4) {
    data[i] = lr[data[i]];
    data[i + 1] = lg[data[i + 1]];
    data[i + 2] = lb[data[i + 2]];
  }
}

// ── Clarity ──

/// Separable box blur; returns RGB floats at an RGBA stride (alpha unused).
Float32List boxBlur(Uint8List data, int width, int height, num radius) {
  final n = width * height;
  final r = math.max(1, (radius + 0.5).floor());
  final tmp = Float32List(n * 3);
  final out = Float32List(n * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      double sr = 0, sg = 0, sb = 0;
      var count = 0;
      for (var dx = -r; dx <= r; dx++) {
        final nx = math.min(width - 1, math.max(0, x + dx));
        final i = (y * width + nx) * 4;
        sr += data[i];
        sg += data[i + 1];
        sb += data[i + 2];
        count++;
      }
      final t = (y * width + x) * 3;
      tmp[t] = sr / count;
      tmp[t + 1] = sg / count;
      tmp[t + 2] = sb / count;
    }
  }
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      double sr = 0, sg = 0, sb = 0;
      var count = 0;
      for (var dy = -r; dy <= r; dy++) {
        final ny = math.min(height - 1, math.max(0, y + dy));
        final t = (ny * width + x) * 3;
        sr += tmp[t];
        sg += tmp[t + 1];
        sb += tmp[t + 2];
        count++;
      }
      final o = (y * width + x) * 4;
      out[o] = sr / count;
      out[o + 1] = sg / count;
      out[o + 2] = sb / count;
    }
  }
  return out;
}

/// Midtone-weighted unsharp mask (negative softens).
void applyClarity(Uint8List data, int width, int height, double amount, [num radius = 2]) {
  if (amount == 0) return;
  final r = math.max(1, math.min(4, (radius + 0.5).floor()));
  final blurred = boxBlur(data, width, height, r);
  for (var i = 0; i < width * height; i++) {
    final p = i * 4;
    final oR = data[p], oG = data[p + 1], oB = data[p + 2];
    final L = rec709Luminance(oR / 255, oG / 255, oB / 255);
    final blend = amount * 4 * L * (1 - L);
    data[p] = math.min(255, math.max(0, jsRound(oR + (oR - blurred[p]) * blend)));
    data[p + 1] = math.min(255, math.max(0, jsRound(oG + (oG - blurred[p + 1]) * blend)));
    data[p + 2] = math.min(255, math.max(0, jsRound(oB + (oB - blurred[p + 2]) * blend)));
  }
}
