// Photo → frame PNG (PLAN.md §8.3): rotate, crop, resize, dither, indexed PNG,
// sha256. Pure Dart and plain data in and out, so it runs in `Isolate.run`.

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'dither.dart';
import 'palette.dart';
import 'png_encoder.dart';
import 'resize.dart';

/// The look presets (app-flow §3.3, D2). Advanced settings are any [DitherOptions].
enum Look {
  balanced(DitherOptions()),
  smooth(DitherOptions(kernel: 'jarvis')),
  crisp(DitherOptions(kernel: 'atkinson')),
  grainy(DitherOptions(mode: DitherMode.random));

  const Look(this.options);

  final DitherOptions options;
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
    this.options = const DitherOptions(),
    this.quarterTurns = 0,
    this.crop,
  });

  final Uint8List rgba;
  final int width, height;

  /// The frame model's resolution.
  final int outWidth, outHeight;
  final Palette palette;
  final DitherOptions options;

  /// Clockwise quarter turns, applied before cropping.
  final int quarterTurns;

  /// In the rotated image's pixels; null = centre crop to the model's aspect.
  final CropRect? crop;
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

/// Dithered palette indices, for the preview ([preview] turns them into colours).
Uint8List ditherPhoto(PhotoJob j, {double Function()? random}) {
  final (rgba, w, h) = rotate(j.rgba, j.width, j.height, j.quarterTurns);
  final crop = j.crop ?? CropRect.center(w, h, j.outWidth / j.outHeight);
  final small = cropResize(rgba, w, h, crop, j.outWidth, j.outHeight);
  return dither(small, j.outWidth, j.outHeight, j.palette, j.options, random: random);
}

/// The whole pipeline. [zopfliIterations] 0 skips Zopfli (faster, ~5 % larger).
PreparedPhoto preparePhoto(PhotoJob j, {int zopfliIterations = 15, double Function()? random}) {
  final indices = ditherPhoto(j, random: random);
  final png = PngEncoder.encode(indices, j.outWidth, j.outHeight, j.palette.deviceColors, zopfli: zopfliIterations).bytes;
  return PreparedPhoto(j.outWidth, j.outHeight, indices, png, sha256.convert(png).toString());
}
