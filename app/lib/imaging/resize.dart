// Crop and resize in pure Dart (PLAN.md §8.3 steps 1–2), so every platform makes
// the same pixels.

import 'dart:math' as math;
import 'dart:typed_data';

class CropRect {
  const CropRect(this.x, this.y, this.w, this.h);

  final double x, y, w, h;

  /// The largest centred rect of [aspect] (w/h) in the image, as ink-frame-lab's
  /// `getCroppedCanvas()` does when no crop is set.
  factory CropRect.center(int imageW, int imageH, double aspect) {
    double w, h;
    if (imageW / imageH >= aspect) {
      h = imageH.toDouble();
      w = h * aspect;
    } else {
      w = imageW.toDouble();
      h = w / aspect;
    }
    return CropRect((imageW - w) / 2, (imageH - h) / 2, w, h);
  }

  @override
  String toString() => 'CropRect($x, $y, $w, $h)';
}

/// Resamples [crop] of an RGBA image to [outW]×[outH] with a separable tent filter
/// widened by the scale factor: area-like averaging when shrinking (no aliasing in
/// fine detail), bilinear when enlarging. Alpha is set to 255.
Uint8List cropResize(Uint8List rgba, int srcW, int srcH, CropRect crop, int outW, int outH) {
  final xs = _weights(crop.x, crop.w, srcW, outW);
  final ys = _weights(crop.y, crop.h, srcH, outH);

  // Horizontal pass over the rows the vertical pass needs.
  final rowMin = ys.first.start, rowMax = ys.last.start + ys.last.weights.length;
  final tmp = Float32List((rowMax - rowMin) * outW * 3);
  for (var sy = rowMin; sy < rowMax; sy++) {
    final srcRow = sy * srcW * 4;
    final dstRow = (sy - rowMin) * outW * 3;
    for (var ox = 0; ox < outW; ox++) {
      final c = xs[ox];
      double r = 0, g = 0, b = 0;
      for (var k = 0; k < c.weights.length; k++) {
        final p = srcRow + (c.start + k) * 4, w = c.weights[k];
        r += rgba[p] * w;
        g += rgba[p + 1] * w;
        b += rgba[p + 2] * w;
      }
      final d = dstRow + ox * 3;
      tmp[d] = r;
      tmp[d + 1] = g;
      tmp[d + 2] = b;
    }
  }

  final out = Uint8List(outW * outH * 4);
  for (var oy = 0; oy < outH; oy++) {
    final c = ys[oy];
    for (var ox = 0; ox < outW; ox++) {
      double r = 0, g = 0, b = 0;
      for (var k = 0; k < c.weights.length; k++) {
        final p = ((c.start + k - rowMin) * outW + ox) * 3, w = c.weights[k];
        r += tmp[p] * w;
        g += tmp[p + 1] * w;
        b += tmp[p + 2] * w;
      }
      final d = (oy * outW + ox) * 4;
      out[d] = _byte(r);
      out[d + 1] = _byte(g);
      out[d + 2] = _byte(b);
      out[d + 3] = 255;
    }
  }
  return out;
}

int _byte(double v) => v <= 0 ? 0 : (v >= 255 ? 255 : (v + 0.5).floor());

class _Contrib {
  _Contrib(this.start, this.weights);

  final int start;
  final Float64List weights;
}

List<_Contrib> _weights(double origin, double span, int srcSize, int outSize) {
  final scale = span / outSize; // source pixels per output pixel
  final support = math.max(1.0, scale); // tent half-width in source pixels
  final out = <_Contrib>[];
  for (var o = 0; o < outSize; o++) {
    final center = origin + (o + 0.5) * scale; // in source pixel coordinates
    var lo = (center - support).floor();
    var hi = (center + support).ceil();
    lo = math.max(lo, 0);
    hi = math.min(hi, srcSize);
    final ws = <double>[];
    var sum = 0.0;
    for (var s = lo; s < hi; s++) {
      final w = math.max(0.0, 1 - ((s + 0.5) - center).abs() / support);
      ws.add(w);
      sum += w;
    }
    if (sum == 0) {
      // Degenerate (tiny crops at an edge): nearest pixel.
      final s = center.floor().clamp(0, srcSize - 1);
      out.add(_Contrib(s, Float64List.fromList([1])));
      continue;
    }
    // Trim zero weights at the ends.
    var a = 0, b = ws.length;
    while (a < b - 1 && ws[a] == 0) {
      a++;
    }
    while (b > a + 1 && ws[b - 1] == 0) {
      b--;
    }
    out.add(_Contrib(lo + a, Float64List.fromList([for (var i = a; i < b; i++) ws[i] / sum])));
  }
  return out;
}

/// Rotates an RGBA image clockwise by [turns] quarter turns (the Prepare screen's
/// rotate button). Returns the pixels and the new width and height.
(Uint8List, int, int) rotate(Uint8List rgba, int width, int height, int turns) {
  final t = turns % 4;
  if (t == 0) return (rgba, width, height);
  final (w2, h2) = t == 2 ? (width, height) : (height, width);
  final out = Uint8List(rgba.length);
  final src = Uint32List.view(rgba.buffer, rgba.offsetInBytes, width * height);
  final dst = Uint32List.view(out.buffer, 0, width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final (nx, ny) = switch (t) {
        1 => (height - 1 - y, x),
        2 => (width - 1 - x, height - 1 - y),
        _ => (y, width - 1 - x),
      };
      dst[ny * w2 + nx] = src[y * width + x];
    }
  }
  return (out, w2, h2);
}
