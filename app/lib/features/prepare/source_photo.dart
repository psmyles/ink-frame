import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// A picked photo, decoded to RGBA (downscaled so its long side is at most
/// [SourcePhoto.maxSide]: plenty for cropping to a frame, and bounded memory).
class SourcePhoto {
  SourcePhoto(this.name, this.rgba, this.width, this.height, this.image);

  static const maxSide = 2400;

  final String name;
  final Uint8List rgba;
  final int width, height;

  /// For drawing in the crop editor.
  final ui.Image image;

  static Future<SourcePhoto?> decode(String name, Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (w, h) {
        final long = w > h ? w : h;
        if (long <= maxSide) return ui.TargetImageSize(width: w, height: h);
        final f = maxSide / long;
        return ui.TargetImageSize(width: (w * f).round(), height: (h * f).round());
      });
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return SourcePhoto(name, data.buffer.asUint8List(), img.width, img.height, img);
    } catch (_) {
      return null; // "Couldn't open this photo"
    }
  }
}

const _extensions = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'bmp'];

/// Photo library on phones, a file dialog on computers. Returns (name, bytes).
Future<List<(String, Uint8List)>> pickPhotos() async {
  final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
  final List<XFile> files;
  if (mobile) {
    files = await ImagePicker().pickMultiImage(requestFullMetadata: false);
  } else {
    files = await openFiles(acceptedTypeGroups: [const XTypeGroup(label: 'Photos', extensions: _extensions)]);
  }
  return [for (final f in files) (f.name, await f.readAsBytes())];
}

bool isPhotoFile(String path) => _extensions.contains(path.split('.').last.toLowerCase());
