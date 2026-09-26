// Port of reference/ink-frame-lab/js/dithering.js (PLAN.md §8.3). Pure Dart.
//
// Every function takes RGBA bytes (alpha ignored) and returns palette indices, one
// byte per pixel. Arithmetic follows the JS exactly (doubles, with the diffusion
// buffer in a Float32List like the JS Float32Array) so results match the golden
// vectors in shared/test-vectors/dither.json bit for bit.

import 'dart:math' as math;
import 'dart:typed_data';

import 'palette.dart';

enum DitherMode { quantization, errorDiffusion, ordered, random }

enum RandomType { luma, rgb }

/// Error-diffusion kernels: `[dx, dy, weight]` and the divisor.
class Kernel {
  const Kernel(this.divisor, this.weights);

  final int divisor;
  final List<List<int>> weights;

  static const all = <String, Kernel>{
    'floydSteinberg': Kernel(16, [[1, 0, 7], [-1, 1, 3], [0, 1, 5], [1, 1, 1]]),
    'atkinson': Kernel(8, [[1, 0, 1], [2, 0, 1], [-1, 1, 1], [0, 1, 1], [1, 1, 1], [0, 2, 1]]),
    'falseFloydSteinberg': Kernel(8, [[1, 0, 3], [0, 1, 3], [1, 1, 2]]),
    'jarvis': Kernel(48, [[1, 0, 7], [2, 0, 5], [-2, 1, 3], [-1, 1, 5], [0, 1, 7], [1, 1, 5], [2, 1, 3], [-2, 2, 1], [-1, 2, 3], [0, 2, 5], [1, 2, 3], [2, 2, 1]]),
    'stucki': Kernel(42, [[1, 0, 8], [2, 0, 4], [-2, 1, 2], [-1, 1, 4], [0, 1, 8], [1, 1, 4], [2, 1, 2], [-2, 2, 1], [-1, 2, 2], [0, 2, 4], [1, 2, 2], [2, 2, 1]]),
    'burkes': Kernel(32, [[1, 0, 8], [2, 0, 4], [-2, 1, 2], [-1, 1, 4], [0, 1, 8], [1, 1, 4], [2, 1, 2]]),
    'sierra3': Kernel(32, [[1, 0, 5], [2, 0, 3], [-2, 1, 2], [-1, 1, 4], [0, 1, 5], [1, 1, 4], [2, 1, 2], [-1, 2, 2], [0, 2, 3], [1, 2, 2]]),
    'sierra2': Kernel(16, [[1, 0, 4], [2, 0, 3], [-2, 1, 1], [-1, 1, 2], [0, 1, 3], [1, 1, 2], [2, 1, 1]]),
    'sierra2_4a': Kernel(4, [[1, 0, 2], [-1, 1, 1], [0, 1, 1]]),
  };
}

/// The ink-frame-lab options (sidebar), with its defaults.
class DitherOptions {
  const DitherOptions({
    this.mode = DitherMode.errorDiffusion,
    this.kernel = 'floydSteinberg',
    this.serpentine = true,
    this.orderedW = 4,
    this.orderedH = 4,
    this.randomType = RandomType.luma,
  });

  final DitherMode mode;
  final String kernel;
  final bool serpentine;
  final int orderedW;
  final int orderedH;
  final RandomType randomType;
}

Uint8List dither(Uint8List rgba, int width, int height, Palette palette, DitherOptions o, {double Function()? random}) =>
    switch (o.mode) {
      DitherMode.quantization => quantize(rgba, width, height, palette.colors),
      DitherMode.errorDiffusion => errorDiffusion(rgba, width, height, palette.colors, o.kernel, o.serpentine),
      DitherMode.ordered => ordered(rgba, width, height, palette.colors, o.orderedW, o.orderedH),
      DitherMode.random => randomDither(rgba, width, height, palette.colors, o.randomType, random ?? math.Random().nextDouble),
    };

/// Squared RGB distance; the first minimum wins.
int nearestPaletteColor(num r, num g, num b, List<List<int>> palette) {
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < palette.length; i++) {
    final p = palette[i];
    final dr = r - p[0], dg = g - p[1], db = b - p[2];
    final d = dr * dr + dg * dg + db * db;
    if (d < bestDist) {
      bestDist = d.toDouble();
      best = i;
    }
  }
  return best;
}

double _clamp(double v) => math.max(0, math.min(255, v));

Uint8List errorDiffusion(Uint8List rgba, int width, int height, List<List<int>> palette, String kernelName, bool serpentine) {
  final n = width * height;
  final buf = Float32List(n * 3);
  for (var i = 0; i < n; i++) {
    buf[i * 3] = rgba[i * 4].toDouble();
    buf[i * 3 + 1] = rgba[i * 4 + 1].toDouble();
    buf[i * 3 + 2] = rgba[i * 4 + 2].toDouble();
  }
  final kernel = Kernel.all[kernelName] ?? Kernel.all['floydSteinberg']!;
  final divisor = kernel.divisor;
  final weights = kernel.weights;
  for (var y = 0; y < height; y++) {
    final ltr = !serpentine || y % 2 == 0;
    final xStart = ltr ? 0 : width - 1, xEnd = ltr ? width : -1, xStep = ltr ? 1 : -1;
    for (var x = xStart; x != xEnd; x += xStep) {
      final idx = (y * width + x) * 3;
      final or = _clamp(buf[idx]), og = _clamp(buf[idx + 1]), ob = _clamp(buf[idx + 2]);
      final p = palette[nearestPaletteColor(or, og, ob, palette)];
      final nr = p[0], ng = p[1], nb = p[2];
      buf[idx] = nr.toDouble();
      buf[idx + 1] = ng.toDouble();
      buf[idx + 2] = nb.toDouble();
      final er = or - nr, eg = og - ng, eb = ob - nb;
      for (final w in weights) {
        final nx = x + (ltr ? w[0] : -w[0]), ny = y + w[1];
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        final j = (ny * width + nx) * 3;
        buf[j] += er * w[2] / divisor;
        buf[j + 1] += eg * w[2] / divisor;
        buf[j + 2] += eb * w[2] / divisor;
      }
    }
  }
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = nearestPaletteColor(_clamp(buf[i * 3]), _clamp(buf[i * 3 + 1]), _clamp(buf[i * 3 + 2]), palette);
  }
  return out;
}

List<List<int>> bayerMatrix(int size) {
  if (size == 1) return [[0]];
  final half = bayerMatrix(size ~/ 2), n = half.length, m = n * 2;
  final mat = List.generate(m, (_) => List.filled(m, 0));
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final v = half[y][x];
      mat[y][x] = 4 * v;
      mat[y][x + n] = 4 * v + 2;
      mat[y + n][x] = 4 * v + 3;
      mat[y + n][x + n] = 4 * v + 1;
    }
  }
  return mat;
}

Uint8List ordered(Uint8List rgba, int width, int height, List<List<int>> palette, int mw, int mh) {
  // 2^ceil(log2(max(mw, mh, 2))), in integers.
  var po2 = 1;
  while (po2 < math.max(math.max(mw, mh), 2)) {
    po2 *= 2;
  }
  final bayer = bayerMatrix(po2), maxVal = po2 * po2;
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final t = (bayer[y % po2][x % po2] / maxVal - 0.5) * (255 / palette.length) * 1.5;
      out[i ~/ 4] = nearestPaletteColor(
        _clamp(rgba[i] + t),
        _clamp(rgba[i + 1] + t),
        _clamp(rgba[i + 2] + t),
        palette,
      );
    }
  }
  return out;
}

/// Random noise of strength 40; [random] is injectable for tests.
Uint8List randomDither(Uint8List rgba, int width, int height, List<List<int>> palette, RandomType type, double Function() random) {
  const sc = 40;
  final n = width * height;
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final pi = i * 4;
    double r = rgba[pi].toDouble(), g = rgba[pi + 1].toDouble(), b = rgba[pi + 2].toDouble();
    if (type == RandomType.rgb) {
      r = _clamp(r + (random() - .5) * sc);
      g = _clamp(g + (random() - .5) * sc);
      b = _clamp(b + (random() - .5) * sc);
    } else {
      final noise = (random() - .5) * sc;
      r = _clamp(r + noise);
      g = _clamp(g + noise);
      b = _clamp(b + noise);
    }
    out[i] = nearestPaletteColor(r, g, b, palette);
  }
  return out;
}

Uint8List quantize(Uint8List rgba, int width, int height, List<List<int>> palette) {
  final n = width * height;
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = nearestPaletteColor(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2], palette);
  }
  return out;
}

/// Indices → RGBA in the calibrated colours: what the panel will show.
Uint8List preview(Uint8List indices, Palette palette) {
  final out = Uint8List(indices.length * 4);
  for (var i = 0; i < indices.length; i++) {
    final c = palette.colors[indices[i]];
    out[i * 4] = c[0];
    out[i * 4 + 1] = c[1];
    out[i * 4 + 2] = c[2];
    out[i * 4 + 3] = 255;
  }
  return out;
}
