// opendithering's Auto-tune: autoExpose → colorTune → hueTune, ported from
// reference/opendithering/src/processing/{autoexpose,colortune,huetune}.ts (MIT).
// Inputs are already at the display size.

import 'dart:math' as math;
import 'dart:typed_data';

import 'color_space.dart';
import 'od_pipeline.dart';
import 'palette.dart';
import 'tone.dart';

double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

class AutoTuneResult {
  const AutoTuneResult(this.afterExpose, this.afterColor, this.settings, this.colorIterations, this.hueIterations);

  final OdSettings afterExpose, afterColor, settings;
  final int colorIterations, hueIterations;
}

/// The three steps as opendithering's Auto-tune button runs them.
AutoTuneResult autoTune(Uint8List rgba, int w, int h, Palette palette, [OdSettings start = OdSettings.balanced]) {
  final exposed = autoExpose(rgba, w, h, palette, start);
  final (colored, ci) = colorTune(rgba, w, h, palette, exposed);
  final (tuned, hi) = hueTune(rgba, w, h, palette, colored);
  return AutoTuneResult(exposed, colored, tuned, ci, hi);
}

/// (black L, white L − black L) of the palette in OKLab.
(double, double) _paletteLRange(Palette p) {
  final ls = [for (final c in p.colors) rgbToOklab(c[0], c[1], c[2])[0]]..sort();
  return (ls.first, ls.last - ls.first);
}

/// The OKLab lightness remap the tuners apply to their reference image.
Uint8List _drcReference(Uint8List rgba, Palette p) {
  final (blackL, range) = _paletteLRange(p);
  final d = Uint8List.fromList(rgba);
  final lab = Float64List(3);
  for (var i = 0; i < d.length; i += 4) {
    rgbToOklabInto(d[i], d[i + 1], d[i + 2], lab);
    final (r, g, b) = oklabToRgb(blackL + lab[0] * range, lab[1], lab[2]);
    d[i] = r;
    d[i + 1] = g;
    d[i + 2] = b;
  }
  return d;
}

// ── Auto expose ──

OdSettings autoExpose(Uint8List rgba, int w, int h, Palette palette, OdSettings s) {
  const targetMeanL = 0.55, targetStddevL = 0.27, shadowThresh = 0.35, highlightThresh = 0.85;
  final d = _drcReference(rgba, palette);
  final n = d.length ~/ 4;
  double sumL = 0, sumL2 = 0, shadowSum = 0;
  var shadowCount = 0, highlightCount = 0;
  final lab = Float64List(3);
  for (var i = 0; i < d.length; i += 4) {
    rgbToOklabInto(d[i], d[i + 1], d[i + 2], lab);
    final L = lab[0];
    sumL += L;
    sumL2 += L * L;
    if (L < shadowThresh) {
      shadowSum += L;
      shadowCount++;
    }
    if (L > highlightThresh) highlightCount++;
  }
  final meanL = sumL / n;
  final stddevL = math.sqrt(math.max(0, sumL2 / n - meanL * meanL));
  final shadowMeanL = shadowCount > 0 ? shadowSum / shadowCount : shadowThresh;
  final highlightFraction = highlightCount / n;

  final exposure = meanL > 0.001 ? _clamp(targetMeanL / meanL, 0.5, 2.0) : 1.0;
  var contrast = 1.0, strength = 0.0, shadowBoost = 0.0, highlightCompress = 1.0;
  if (s.toneMode == ToneMode.contrast) {
    contrast = stddevL > 0.001 ? _clamp(targetStddevL / stddevL, 0.5, 2.0) : 1.0;
  } else {
    strength = stddevL > 0.001 ? _clamp(targetStddevL / (stddevL * 2), 0.0, 1.0) : 0.5;
    shadowBoost = shadowMeanL < 0.20 ? _clamp(0.3 * (0.20 - shadowMeanL) / 0.20, 0.0, 0.3) : 0.0;
    highlightCompress = highlightFraction > 0.05 ? _clamp(1.0 + highlightFraction * 4, 1.0, 3.0) : 1.0;
  }
  return s.copyWith(
    exposure: exposure,
    saturation: 1.0,
    contrast: contrast,
    strength: strength,
    shadowBoost: shadowBoost,
    highlightCompress: highlightCompress,
    midpoint: 0.5,
    redGain: 1.0,
    greenGain: 1.0,
    blueGain: 1.0,
    compressDynamicRange: true,
  );
}

// ── Colour tune ──

class _Stats {
  double meanC = 0, meanA = 0, meanBv = 0, meanR = 0, meanG = 0, meanBlue = 0;
}

_Stats _imageStatsRgba(Uint8List d) {
  final s = _Stats();
  final n = d.length ~/ 4;
  final lab = Float64List(3);
  for (var i = 0; i < d.length; i += 4) {
    rgbToOklabInto(d[i], d[i + 1], d[i + 2], lab);
    s.meanC += math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    s.meanA += lab[1];
    s.meanBv += lab[2];
    s.meanR += d[i] / 255;
    s.meanG += d[i + 1] / 255;
    s.meanBlue += d[i + 2] / 255;
  }
  s
    ..meanC /= n
    ..meanA /= n
    ..meanBv /= n
    ..meanR /= n
    ..meanG /= n
    ..meanBlue /= n;
  return s;
}

/// Stats of a dithered image, from its index histogram (only palette colours occur).
/// Sums in pixel order like the JS so the floating-point result is identical.
_Stats _imageStatsIndices(Uint8List idx, Palette p) {
  final s = _Stats();
  final lab = [for (final c in p.colors) rgbToOklab(c[0], c[1], c[2])];
  final chroma = [for (final l in lab) math.sqrt(l[1] * l[1] + l[2] * l[2])];
  for (final k in idx) {
    final c = p.colors[k];
    s.meanC += chroma[k];
    s.meanA += lab[k][1];
    s.meanBv += lab[k][2];
    s.meanR += c[0] / 255;
    s.meanG += c[1] / 255;
    s.meanBlue += c[2] / 255;
  }
  final n = idx.length;
  s
    ..meanC /= n
    ..meanA /= n
    ..meanBv /= n
    ..meanR /= n
    ..meanG /= n
    ..meanBlue /= n;
  return s;
}

double _colorLoss(_Stats r, _Stats c) =>
    (r.meanC - c.meanC).abs() + (r.meanA - c.meanA).abs() + (r.meanBv - c.meanBv).abs();

double _adjustGain(double current, double refMean, double prevMean, double initial) {
  if (prevMean < 0.001) return current;
  final lo = initial > 0.001 ? initial * 0.85 : 0.0;
  final hi = initial > 0.001 ? initial * 1.15 : 0.15;
  final candidate = current > 0.001 ? current * (1 + (refMean / prevMean - 1) * 0.3) : (refMean - prevMean) * 0.3;
  return _clamp(_clamp(candidate, lo, hi), 0.5, 2.0);
}

(OdSettings, int) colorTune(Uint8List rgba, int w, int h, Palette palette, OdSettings s, {int iterations = 12}) {
  final ref = _imageStatsRgba(s.compressDynamicRange ? _drcReference(rgba, palette) : rgba);
  var saturation = s.saturation;
  var r = 1.0, g = 1.0, b = 1.0;
  OdSettings with_(double r, double g, double b) => s.copyWith(saturation: saturation, redGain: r, greenGain: g, blueGain: b);

  var prev = _imageStatsIndices(runPipeline(rgba, w, h, palette, with_(r, g, b)), palette);
  var prevLoss = _colorLoss(ref, prev);
  var best = with_(r, g, b);
  var runs = 0;
  for (var i = 0; i < iterations; i++) {
    final nr = _adjustGain(r, ref.meanR, prev.meanR, 1);
    final ng = _adjustGain(g, ref.meanG, prev.meanG, 1);
    final nb = _adjustGain(b, ref.meanBlue, prev.meanBlue, 1);
    final stats = _imageStatsIndices(runPipeline(rgba, w, h, palette, with_(nr, ng, nb)), palette);
    final loss = _colorLoss(ref, stats);
    if (loss >= prevLoss - 1e-4) break;
    best = with_(nr, ng, nb);
    prevLoss = loss;
    prev = stats;
    r = nr;
    g = ng;
    b = nb;
    runs++;
  }
  return (best, runs);
}

// ── Hue tune ──

class _Band {
  _Band(this.refMeanC, this.dithMeanC, this.count);

  final double refMeanC, dithMeanC, count;
}

/// Per hue band: chroma of the mean OKLab (a, b) of the reference and of the blurred
/// dithered image, over the reference's chromatic pixels.
List<_Band> _bandStats(Uint8List ref, Float32List dith) {
  final refA = Float64List(6), refB = Float64List(6), dA = Float64List(6), dB = Float64List(6), counts = Float64List(6);
  final lab = Float64List(3);
  for (var i = 0; i < ref.length; i += 4) {
    final rr = ref[i], rg = ref[i + 1], rb = ref[i + 2];
    final rn = rr / 255, gn = rg / 255, bn = rb / 255;
    final mx = math.max(rn, math.max(gn, bn)), mn = math.min(rn, math.min(gn, bn));
    final d = mx - mn;
    if (d < 0.05) continue;
    double hue;
    if (mx == rn) {
      hue = ((gn - bn) / d + (gn < bn ? 6 : 0)) / 6;
    } else if (mx == gn) {
      hue = ((bn - rn) / d + 2) / 6;
    } else {
      hue = ((rn - gn) / d + 4) / 6;
    }
    final hx = hue * 6;
    final band = hx.floor() % 6, next = (band + 1) % 6;
    final t = hx - hx.floor();
    rgbToOklabInto(rr, rg, rb, lab);
    refA[band] += (1 - t) * lab[1];
    refB[band] += (1 - t) * lab[2];
    refA[next] += t * lab[1];
    refB[next] += t * lab[2];
    rgbToOklabInto(dith[i], dith[i + 1], dith[i + 2], lab);
    dA[band] += (1 - t) * lab[1];
    dB[band] += (1 - t) * lab[2];
    dA[next] += t * lab[1];
    dB[next] += t * lab[2];
    counts[band] += 1 - t;
    counts[next] += t;
  }
  return [
    for (var i = 0; i < 6; i++)
      if (counts[i] == 0)
        _Band(0, 0, 0)
      else
        _Band(
          math.sqrt(math.pow(refA[i] / counts[i], 2) + math.pow(refB[i] / counts[i], 2)),
          math.sqrt(math.pow(dA[i] / counts[i], 2) + math.pow(dB[i] / counts[i], 2)),
          counts[i],
        ),
  ];
}

double _hueLoss(List<_Band> stats, int minPixels) {
  var total = 0.0;
  for (final s in stats) {
    if (s.count >= minPixels) total += (s.refMeanC - s.dithMeanC).abs();
  }
  return total;
}

Uint8List _measuredRgba(Uint8List idx, Palette p) {
  final out = Uint8List(idx.length * 4);
  for (var i = 0; i < idx.length; i++) {
    final c = p.colors[idx[i]];
    out[i * 4] = c[0];
    out[i * 4 + 1] = c[1];
    out[i * 4 + 2] = c[2];
    out[i * 4 + 3] = 255;
  }
  return out;
}

(OdSettings, int) hueTune(Uint8List rgba, int w, int h, Palette palette, OdSettings s, {int iterations = 20}) {
  const blurRadius = 4, floor = 0.25, ceiling = 4.0;
  final ref = s.compressDynamicRange ? _drcReference(rgba, palette) : rgba;
  final minPixels = math.max(50, jsRound(ref.length / 4 * 0.001));
  var bands = <double>[1, 1, 1, 1, 1, 1];

  List<_Band> statsFor(List<double> b) {
    final idx = runPipeline(rgba, w, h, palette, s.copyWith(hueSatBands: b));
    return _bandStats(ref, boxBlur(_measuredRgba(idx, palette), w, h, blurRadius));
  }

  var prev = statsFor(bands);
  var prevLoss = _hueLoss(prev, minPixels);
  var best = List<double>.of(bands);
  var runs = 0;
  for (var i = 0; i < iterations; i++) {
    var allCapped = true;
    for (var k = 0; k < 6; k++) {
      final st = prev[k];
      if (st.count < minPixels || st.dithMeanC < 0.001) continue;
      final ratio = st.refMeanC / st.dithMeanC;
      if (!((ratio > 1.01 && bands[k] >= ceiling) || (ratio < 0.99 && bands[k] <= floor))) allCapped = false;
    }
    if (allCapped) break;

    final next = [
      for (var k = 0; k < 6; k++)
        if (prev[k].count < minPixels || prev[k].dithMeanC < 0.001)
          bands[k]
        else
          _clamp(_clamp(bands[k] * (1 + (prev[k].refMeanC / prev[k].dithMeanC - 1) * 0.3), bands[k] * 0.75, bands[k] * 1.25), floor, ceiling),
    ];
    final stats = statsFor(next);
    final loss = _hueLoss(stats, minPixels);
    if (!loss.isFinite || loss >= prevLoss - 1e-4) break;
    best = List.of(next);
    prevLoss = loss;
    prev = stats;
    bands = next;
    runs++;
  }
  return (s.copyWith(hueSatBands: best), runs);
}
