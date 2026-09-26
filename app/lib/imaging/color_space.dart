// sRGB, linear RGB, CIELAB and OKLab conversions, ported from
// reference/opendithering/src/processing/colorspace.ts (MIT).

import 'dart:math' as math;
import 'dart:typed_data';

/// JavaScript's Math.round: halves round up (towards +∞).
int jsRound(double v) => (v + 0.5).floor();

/// Cube root accurate to the last bit or so (Dart has no cbrt): pow, then one
/// Newton step, which matches JS Math.cbrt in practice.
double cbrt(double x) {
  if (x == 0 || x.isNaN || x.isInfinite) return x;
  final a = x.abs();
  var y = math.pow(a, 1 / 3).toDouble();
  y = y - (y * y * y - a) / (3 * y * y);
  return x < 0 ? -y : y;
}

final Float64List _linearTable = Float64List.fromList([for (var c = 0; c < 256; c++) _srgbToLinear(c.toDouble())]);

double _srgbToLinear(double c) {
  final v = c / 255;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// 0–255 sRGB (any number) → linear 0–1.
double srgbToLinear(num c) => (c is int && c >= 0 && c < 256) ? _linearTable[c] : _srgbToLinear(c.toDouble());

/// Linear → 0–255 sRGB, rounded like the JS.
int linearToSrgb(double c) {
  final v = c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
  return jsRound(math.min(1.0, math.max(0.0, v)) * 255);
}

/// sRGB → OKLab into [out] (L, a, b).
void rgbToOklabInto(num r, num g, num b, Float64List out) =>
    linearToOklabInto(srgbToLinear(r), srgbToLinear(g), srgbToLinear(b), out);

/// Linear RGB (0–1) → OKLab into [out].
void linearToOklabInto(double lr, double lg, double lb, Float64List out) {
  final l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  final m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  final s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  out[0] = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  out[1] = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  out[2] = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
}

List<double> rgbToOklab(num r, num g, num b) {
  final o = Float64List(3);
  rgbToOklabInto(r, g, b, o);
  return o;
}

/// OKLab → sRGB ints (clamped).
(int, int, int) oklabToRgb(double L, double a, double b) {
  final l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  final m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  final s_ = L - 0.0894841775 * a - 1.2914855480 * b;
  final l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
  return (
    linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s),
  );
}

const _d65 = [0.95047, 1.00000, 1.08883];

double _f(double t) => t > 0.008856 ? cbrt(t) : (7.787 * t) + (16 / 116);

void rgbToLabInto(num r, num g, num b, Float64List out) {
  final lr = srgbToLinear(r), lg = srgbToLinear(g), lb = srgbToLinear(b);
  final x = lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375;
  final y = lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750;
  final z = lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041;
  final fx = _f(x / _d65[0]), fy = _f(y / _d65[1]), fz = _f(z / _d65[2]);
  out[0] = 116 * fy - 16;
  out[1] = 500 * (fx - fy);
  out[2] = 200 * (fy - fz);
}

double _fInv(double t) {
  final t3 = t * t * t;
  return t3 > 0.008856 ? t3 : (t - 16 / 116) / 7.787;
}

(int, int, int) labToRgb(double L, double a, double b) {
  final fy = (L + 16) / 116, fx = fy + a / 500, fz = fy - b / 200;
  final x = _d65[0] * _fInv(fx), y = _d65[1] * _fInv(fy), z = _d65[2] * _fInv(fz);
  return (
    linearToSrgb(3.2404542 * x - 1.5371385 * y - 0.4985314 * z),
    linearToSrgb(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z),
    linearToSrgb(0.0556434 * x - 0.2040259 * y + 1.0572252 * z),
  );
}

/// Linear luminance of an sRGB colour.
double rec709Luminance(num r, num g, num b) =>
    0.2126729 * srgbToLinear(r) + 0.7151522 * srgbToLinear(g) + 0.0721750 * srgbToLinear(b);
