// The app's processing (Automatic, as in Prepare), run on the computer with a chosen set
// of panel colours, for checking a calibration on the frame (tools/calibration/README.md).
//
//   cd app && dart run tool/calibration_render.dart [--colours colours.json] OUT_DIR picture.png…
//
// colours.json, e.g. {"red": "#8A2520", …}, replaces those Spectra 6 colours from
// shared/presets.json. For each picture it writes OUT_DIR/<name>.frame.png (what the app
// would upload; show it with firmware/tools/console.py show) and <name>.preview.png (the
// app's preview of it).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/imaging/pipeline.dart';

void main(List<String> arguments) {
  final args = [...arguments];
  var colours = <String, dynamic>{};
  final at = args.indexOf('--colours');
  if (at >= 0) {
    colours = jsonDecode(File(args[at + 1]).readAsStringSync()) as Map<String, dynamic>;
    args.removeRange(at, at + 2);
  }
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/calibration_render.dart [--colours colours.json] OUT_DIR picture.png…');
    exit(64);
  }
  final out = Directory(args.removeAt(0))..createSync(recursive: true);

  final presets = jsonDecode(File('../shared/presets.json').readAsStringSync()) as Map<String, dynamic>;
  final json = (presets['palettes'] as List).cast<Map<String, dynamic>>().firstWhere((p) => p['id'] == 'spectra6');
  for (final c in (json['colors'] as List).cast<Map<String, dynamic>>()) {
    if (colours[c['name']] case final String hex) c['color'] = hex;
  }
  final palette = Palette.fromJson(json);

  for (final path in args) {
    final src = img.decodeImage(File(path).readAsBytesSync())!.convert(numChannels: 4);
    final rgba = Uint8List.fromList(src.getBytes(order: img.ChannelOrder.rgba));
    final photo = preparePhoto(
      PhotoJob(rgba: rgba, width: src.width, height: src.height, outWidth: 800, outHeight: 480, palette: palette),
      zopfliIterations: 0,
    );
    final name = path.split('/').last.replaceAll(RegExp(r'\.png$'), '');
    File('${out.path}/$name.frame.png').writeAsBytesSync(photo.png);
    final preview = img.Image(width: photo.width, height: photo.height);
    for (var i = 0; i < photo.indices.length; i++) {
      final c = palette.colors[photo.indices[i]];
      preview.setPixelRgb(i % photo.width, i ~/ photo.width, c[0], c[1], c[2]);
    }
    File('${out.path}/$name.preview.png').writeAsBytesSync(img.encodePng(preview));
    stdout.writeln('${out.path}/$name.frame.png');
  }
}
