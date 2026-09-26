// Swapping an indexed PNG's palette without touching its pixels: the frame's PNGs
// hold the device colours (pure primaries), and the app shows them in the panel's
// calibrated colours by rewriting PLTE before decoding.

import 'dart:typed_data';

/// Returns [png] with each PLTE entry that equals a colour in [from] replaced by
/// the colour at the same index in [to] (RGB triples). Other chunks are copied.
/// Returns [png] unchanged if it has no PLTE.
Uint8List recolorPng(Uint8List png, List<List<int>> from, List<List<int>> to) {
  final bd = ByteData.sublistView(png);
  var i = 8;
  while (i + 8 <= png.length) {
    final len = bd.getUint32(i);
    final type = String.fromCharCodes(png.sublist(i + 4, i + 8));
    if (type == 'PLTE') {
      final out = Uint8List.fromList(png);
      for (var k = 0; k < len ~/ 3; k++) {
        final p = i + 8 + k * 3;
        for (var j = 0; j < from.length; j++) {
          final f = from[j];
          if (png[p] == f[0] && png[p + 1] == f[1] && png[p + 2] == f[2]) {
            out.setAll(p, to[j]);
            break;
          }
        }
      }
      final crc = _crc32(out, i + 4, 4 + len);
      ByteData.sublistView(out).setUint32(i + 8 + len, crc);
      return out;
    }
    if (type == 'IDAT' || type == 'IEND') break;
    i += 12 + len;
  }
  return png;
}

final _table = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crc32(Uint8List b, int start, int length) {
  var c = 0xFFFFFFFF;
  for (var i = start; i < start + length; i++) {
    c = _table[(c ^ b[i]) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
