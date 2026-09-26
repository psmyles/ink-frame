// How close a dithered picture looks to its source, as one number.
//
// The eye adapts to the frame's paper white and blends neighbouring dots. So the
// dithered image is taken in the panel's measured colours, scaled so the panel's
// white is white (von Kries, per channel in linear light), and both images are
// blurred with a Gaussian in linear light (the dots average as light does). The
// score is the mean OKLab distance ×100 between them: lower is closer; ~2 is a
// just-noticeable difference. The panel's raised black is unavoidable and costs
// every method the same.

import 'dart:math' as math;
import 'dart:typed_data';

import 'color_space.dart';
import 'palette.dart';

class Fidelity {
  Fidelity(Uint8List sourceRgba, this.width, this.height, this.palette, {this.sigma = 1.5})
      : _target = _oklab(_blur(_linear(sourceRgba), width, height, sigma)),
        _white = _whiteOf(palette);

  final int width, height;
  final Palette palette;
  final double sigma;
  final Float32List _target;
  final List<double> _white;

  static List<double> _whiteOf(Palette p) {
    var best = 0, bestY = -1.0;
    for (var i = 0; i < p.length; i++) {
      final c = p.colors[i];
      final y = rec709Luminance(c[0], c[1], c[2]);
      if (y > bestY) {
        bestY = y;
        best = i;
      }
    }
    final w = p.colors[best];
    return [srgbToLinear(w[0]), srgbToLinear(w[1]), srgbToLinear(w[2])];
  }

  /// Mean ΔE_OK ×100 of dithered [indices] against the source.
  double score(Uint8List indices) => measure(indices).$1;

  /// (mean ΔE_OK ×100, mean SSIM of OKLab lightness in 9×9 windows): colour
  /// accuracy and how well local contrast and detail survive.
  (double, double) measure(Uint8List indices) {
    final lin = Float32List(indices.length * 3);
    final pal = [
      for (final c in palette.colors) [srgbToLinear(c[0]) / _white[0], srgbToLinear(c[1]) / _white[1], srgbToLinear(c[2]) / _white[2]],
    ];
    for (var i = 0; i < indices.length; i++) {
      final c = pal[indices[i]];
      lin[i * 3] = c[0];
      lin[i * 3 + 1] = c[1];
      lin[i * 3 + 2] = c[2];
    }
    final got = _oklab(_blur(lin, width, height, sigma));
    var sum = 0.0;
    for (var i = 0; i < got.length; i += 3) {
      final d0 = got[i] - _target[i], d1 = got[i + 1] - _target[i + 1], d2 = got[i + 2] - _target[i + 2];
      sum += math.sqrt(d0 * d0 + d1 * d1 + d2 * d2);
    }
    return (sum / (got.length / 3) * 100, _ssimL(got, _target));
  }

  /// SSIM on the L channel with a 9×9 box window.
  double _ssimL(Float32List a, Float32List b) {
    final n = width * height;
    final x = Float64List(n), y = Float64List(n);
    for (var i = 0; i < n; i++) {
      x[i] = a[i * 3];
      y[i] = b[i * 3];
    }
    final mx = _box(x), my = _box(y);
    final xx = _box(Float64List.fromList([for (var i = 0; i < n; i++) x[i] * x[i]]));
    final yy = _box(Float64List.fromList([for (var i = 0; i < n; i++) y[i] * y[i]]));
    final xy = _box(Float64List.fromList([for (var i = 0; i < n; i++) x[i] * y[i]]));
    const c1 = 0.0001, c2 = 0.0009; // (0.01·1)², (0.03·1)² for L in 0–1
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final vx = xx[i] - mx[i] * mx[i], vy = yy[i] - my[i] * my[i], cxy = xy[i] - mx[i] * my[i];
      sum += ((2 * mx[i] * my[i] + c1) * (2 * cxy + c2)) / ((mx[i] * mx[i] + my[i] * my[i] + c1) * (vx + vy + c2));
    }
    return sum / n;
  }

  Float64List _box(Float64List v) {
    const r = 4;
    final w = width, h = height;
    final tmp = Float64List(v.length), out = Float64List(v.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var i = -r; i <= r; i++) {
          s += v[y * w + math.min(w - 1, math.max(0, x + i))];
        }
        tmp[y * w + x] = s / (2 * r + 1);
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0.0;
        for (var i = -r; i <= r; i++) {
          s += tmp[math.min(h - 1, math.max(0, y + i)) * w + x];
        }
        out[y * w + x] = s / (2 * r + 1);
      }
    }
    return out;
  }

  static Float32List _linear(Uint8List rgba) {
    final out = Float32List(rgba.length ~/ 4 * 3);
    for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
      out[j] = srgbToLinear(rgba[i]);
      out[j + 1] = srgbToLinear(rgba[i + 1]);
      out[j + 2] = srgbToLinear(rgba[i + 2]);
    }
    return out;
  }

  static Float32List _oklab(Float32List lin) {
    final out = Float32List(lin.length);
    final o = Float64List(3);
    for (var i = 0; i < lin.length; i += 3) {
      linearToOklabInto(math.max(0, lin[i]), math.max(0, lin[i + 1]), math.max(0, lin[i + 2]), o);
      out[i] = o[0];
      out[i + 1] = o[1];
      out[i + 2] = o[2];
    }
    return out;
  }

  /// Separable Gaussian on 3-channel data, edges clamped.
  static Float32List _blur(Float32List src, int w, int h, double sigma) {
    final r = (sigma * 3).ceil();
    final k = Float64List(2 * r + 1);
    var sum = 0.0;
    for (var i = -r; i <= r; i++) {
      k[i + r] = math.exp(-i * i / (2 * sigma * sigma));
      sum += k[i + r];
    }
    for (var i = 0; i < k.length; i++) {
      k[i] /= sum;
    }
    final tmp = Float32List(src.length), out = Float32List(src.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        double a = 0, b = 0, c = 0;
        for (var i = -r; i <= r; i++) {
          final xx = math.min(w - 1, math.max(0, x + i));
          final p = (y * w + xx) * 3, kv = k[i + r];
          a += src[p] * kv;
          b += src[p + 1] * kv;
          c += src[p + 2] * kv;
        }
        final q = (y * w + x) * 3;
        tmp[q] = a;
        tmp[q + 1] = b;
        tmp[q + 2] = c;
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        double a = 0, b = 0, c = 0;
        for (var i = -r; i <= r; i++) {
          final yy = math.min(h - 1, math.max(0, y + i));
          final p = (yy * w + x) * 3, kv = k[i + r];
          a += tmp[p] * kv;
          b += tmp[p + 1] * kv;
          c += tmp[p + 2] * kv;
        }
        final q = (y * w + x) * 3;
        out[q] = a;
        out[q + 1] = b;
        out[q + 2] = c;
      }
    }
    return out;
  }
}
