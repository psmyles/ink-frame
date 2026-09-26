// Photo → frame PNG (PLAN.md §8.3): rotate, crop, resize, adjust, dither, indexed
// PNG, sha256. Pure Dart and plain data in and out, so it runs in `Isolate.run`.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'auto.dart';
import 'dither.dart' as lab;
import 'od_pipeline.dart';
import 'palette.dart';
import 'png_encoder.dart';
import 'resize.dart';

/// How the dots are laid out (Adjust → More options → Dot pattern).
enum DotPattern {
  /// Floyd–Steinberg in linear light (default).
  fine,

  /// Jarvis–Judice–Ninke: softer, spreads error further.
  smooth,

  /// Atkinson: crisper, loses some shading.
  crisp,

  /// Ordered 4×4 Bayer: a regular pattern.
  grid,

  /// Random noise.
  grainy,
}

/// What the person chose in Adjust (app-flow §3.3). Sliders run −1…1 around
/// Automatic's choice (or around a faithful mapping when Automatic is off).
class PhotoAdjustments {
  const PhotoAdjustments({
    this.automatic = true,
    this.brightness = 0,
    this.contrast = 0,
    this.colour = 0,
    this.pattern = DotPattern.fine,
  });

  final bool automatic;
  final double brightness, contrast, colour;
  final DotPattern pattern;

  bool get isDefault => automatic && brightness == 0 && contrast == 0 && colour == 0 && pattern == DotPattern.fine;

  PhotoAdjustments copyWith({bool? automatic, double? brightness, double? contrast, double? colour, DotPattern? pattern}) =>
      PhotoAdjustments(
        automatic: automatic ?? this.automatic,
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        colour: colour ?? this.colour,
        pattern: pattern ?? this.pattern,
      );
}

/// A decoded photo and what to do with it.
class PhotoJob {
  const PhotoJob({
    required this.rgba,
    required this.width,
    required this.height,
    required this.outWidth,
    required this.outHeight,
    required this.palette,
    this.adjustments = const PhotoAdjustments(),
    this.quarterTurns = 0,
    this.crop,
    this.autoSettings,
  });

  final Uint8List rgba;
  final int width, height;

  /// The frame model's resolution.
  final int outWidth, outHeight;
  final Palette palette;
  final PhotoAdjustments adjustments;

  /// Clockwise quarter turns, applied before cropping.
  final int quarterTurns;

  /// In the rotated image's pixels; null = centre crop to the model's aspect.
  final CropRect? crop;

  /// Automatic's settings for this photo and crop, if already worked out (they take
  /// ~1 s; the Prepare screen keeps them while only sliders move).
  final OdSettings? autoSettings;
}

class PreparedPhoto {
  const PreparedPhoto(this.width, this.height, this.indices, this.png, this.sha256);

  final int width, height;

  /// Palette index per pixel.
  final Uint8List indices;

  /// The file to upload (indexed PNG with the device colours).
  final Uint8List png;

  /// Lower-case hex, as `POST /images/request-upload` wants it.
  final String sha256;
}

/// The photo rotated, cropped and resized to the frame.
Uint8List frameSized(PhotoJob j) {
  final (rgba, w, h) = rotate(j.rgba, j.width, j.height, j.quarterTurns);
  final crop = j.crop ?? CropRect.center(w, h, j.outWidth / j.outHeight);
  return cropResize(rgba, w, h, crop, j.outWidth, j.outHeight);
}

/// Automatic's settings (or the faithful ones) with the sliders applied.
OdSettings settingsFor(PhotoAdjustments a, OdSettings base) {
  var s = base.copyWith(
    exposure: base.exposure * math.pow(2, a.brightness * 0.5),
    saturation: base.saturation * (1 + a.colour * 0.5),
    algorithm: switch (a.pattern) {
      DotPattern.smooth => 'jarvis',
      DotPattern.crisp => 'atkinson',
      _ => 'floyd-steinberg',
    },
  );
  if (a.contrast != 0) {
    final lifted = s.strength == 0 && a.contrast > 0;
    s = s.copyWith(
      strength: (s.strength + a.contrast * 0.6).clamp(0.0, 1.0),
      highlightCompress: lifted ? 1.5 : s.highlightCompress,
    );
  }
  return s;
}

/// Palette indices for the frame (the preview shows them in the calibrated colours).
/// Returns the Automatic settings it used, so callers can reuse them.
(Uint8List, OdSettings?) ditherPhoto(PhotoJob j, {double Function()? random}) {
  final sized = frameSized(j);
  final w = j.outWidth, h = j.outHeight;
  final auto = j.adjustments.automatic ? (j.autoSettings ?? autoSettings(sized, w, h, j.palette)) : null;
  final s = settingsFor(j.adjustments, auto ?? faithful);
  final indices = switch (j.adjustments.pattern) {
    DotPattern.grid => lab.ordered(_adjusted(sized, w, h, j.palette, s), w, h, j.palette.colors, 4, 4),
    DotPattern.grainy => lab.randomDither(_adjusted(sized, w, h, j.palette, s), w, h, j.palette.colors, lab.RandomType.luma,
        random ?? math.Random().nextDouble),
    _ => runPipeline(sized, w, h, j.palette, s),
  };
  return (indices, auto);
}

Uint8List _adjusted(Uint8List rgba, int w, int h, Palette p, OdSettings s) {
  final out = Uint8List.fromList(rgba);
  adjust(out, w, h, p, s);
  return out;
}

/// The whole pipeline. [zopfliIterations] 0 skips Zopfli (faster, ~5 % larger).
PreparedPhoto preparePhoto(PhotoJob j, {int zopfliIterations = 15, double Function()? random}) {
  final (indices, _) = ditherPhoto(j, random: random);
  final png = PngEncoder.encode(indices, j.outWidth, j.outHeight, j.palette.deviceColors, zopfli: zopfliIterations).bytes;
  return PreparedPhoto(j.outWidth, j.outHeight, indices, png, sha256.convert(png).toString());
}
