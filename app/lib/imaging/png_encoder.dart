// Indexed-colour PNG encoder tuned for the smallest files (PLAN.md §8.3 step 5).
//
// Dithered e-ink images use 2–7 colours, so they are written as palette PNGs with
// the fewest bits per pixel that fit the colours actually used. Several encodings
// are tried and the smallest is kept (see [PngEncoder.candidates]).
//
// The firmware decodes with PNGdec (1/2/4/8-bit palette images, any filter), and the
// PLTE holds the palette's device colours, so it gets the pure panel colours back.

import 'dart:io' show ZLibCodec, ZLibOption;
import 'dart:typed_data';

import 'zopfli.dart';

/// Row filter choice: one PNG filter type for every row, or a per-row heuristic.
enum RowFilter { none, sub, up, average, paeth, minSum }

/// How the palette entries are numbered in the file.
enum PaletteOrder {
  /// The original palette order (unused colours dropped).
  original,

  /// Most frequent colour first.
  frequency,
}

class PngCandidate {
  const PngCandidate(this.order, this.bitDepth8, this.filter, this.strategy);

  final PaletteOrder order;

  /// Force 8 bits per pixel instead of the smallest depth.
  final bool bitDepth8;
  final RowFilter filter;
  final int strategy; // ZLibOption.strategy*

  @override
  String toString() => '${order.name}/${bitDepth8 ? '8bit' : 'min'}/${filter.name}/'
      '${const {0: 'default', 1: 'filtered', 2: 'huffman', 3: 'rle', 4: 'fixed'}[strategy]}';
}

class PngEncoded {
  const PngEncoded(this.bytes, this.candidate, this.bitDepth, this.colors);

  final Uint8List bytes;
  final PngCandidate candidate;
  final int bitDepth;

  /// Colours actually used (entries in PLTE).
  final int colors;
}

class PngEncoder {
  /// The encodings tried by default: the ones that won on real photos
  /// (tools/png-bench in app/test/imaging/png_bench_test.dart).
  static const candidates = <PngCandidate>[
    PngCandidate(PaletteOrder.original, false, RowFilter.none, ZLibOption.strategyDefault),
    PngCandidate(PaletteOrder.frequency, false, RowFilter.none, ZLibOption.strategyDefault),
    PngCandidate(PaletteOrder.original, false, RowFilter.none, ZLibOption.strategyFiltered),
    PngCandidate(PaletteOrder.frequency, false, RowFilter.minSum, ZLibOption.strategyDefault),
  ];

  /// Encodes palette [indices] (one byte per pixel) with [palette] RGB colours:
  /// tries [tries] with zlib and keeps the smallest, then (unless [zopfli] is 0)
  /// recompresses that one with [Zopfli] using [zopfli] iterations, which saves
  /// another 5–9 % on dithered photos.
  static PngEncoded encode(Uint8List indices, int width, int height, List<List<int>> palette,
      {List<PngCandidate> tries = candidates, int zopfli = 15}) {
    PngEncoded? best;
    for (final c in tries) {
      final e = encodeWith(indices, width, height, palette, c);
      if (best == null || e.bytes.length < best.bytes.length) best = e;
    }
    if (zopfli <= 0) return best!;
    final z = encodeWith(indices, width, height, palette, best!.candidate, zopfliIterations: zopfli);
    return z.bytes.length < best.bytes.length ? z : best;
  }

  static PngEncoded encodeWith(Uint8List indices, int width, int height, List<List<int>> palette, PngCandidate c,
      {int zopfliIterations = 0}) {
    assert(indices.length == width * height);

    // Keep only used colours, numbered per [c.order].
    final counts = List.filled(palette.length, 0);
    for (final i in indices) {
      counts[i]++;
    }
    final used = [for (var i = 0; i < palette.length; i++) if (counts[i] > 0) i];
    if (c.order == PaletteOrder.frequency) used.sort((a, b) => counts[b].compareTo(counts[a]));
    final remap = Uint8List(palette.length);
    for (var k = 0; k < used.length; k++) {
      remap[used[k]] = k;
    }

    final bitDepth = c.bitDepth8
        ? 8
        : used.length <= 2
            ? 1
            : used.length <= 4
                ? 2
                : used.length <= 16
                    ? 4
                    : 8;
    final rowBytes = (width * bitDepth + 7) >> 3;

    // Pack rows.
    final packed = Uint8List(rowBytes * height);
    final perByte = 8 ~/ bitDepth;
    for (var y = 0; y < height; y++) {
      final row = y * rowBytes;
      for (var x = 0; x < width; x++) {
        final v = remap[indices[y * width + x]];
        final shift = 8 - bitDepth * (x % perByte + 1);
        packed[row + x ~/ perByte] |= v << shift;
      }
    }

    final raw = _filter(packed, rowBytes, height, c.filter);
    final idat = zopfliIterations > 0
        ? Zopfli.zlib(raw, iterations: zopfliIterations)
        : Uint8List.fromList(ZLibCodec(level: 9, memLevel: 9, windowBits: 15, strategy: c.strategy).encode(raw));

    final plte = Uint8List(used.length * 3);
    for (var k = 0; k < used.length; k++) {
      plte.setAll(k * 3, palette[used[k]]);
    }
    final ihdr = ByteData(13)
      ..setUint32(0, width)
      ..setUint32(4, height)
      ..setUint8(8, bitDepth)
      ..setUint8(9, 3) // colour type: palette
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);

    final b = BytesBuilder(copy: false)..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    _chunk(b, 'IHDR', ihdr.buffer.asUint8List());
    _chunk(b, 'PLTE', plte);
    _chunk(b, 'IDAT', idat);
    _chunk(b, 'IEND', Uint8List(0));
    return PngEncoded(b.toBytes(), c, bitDepth, used.length);
  }

  /// Adds the filter byte to each row. Filters work on bytes (bpp = 1 below 8 bits).
  static Uint8List _filter(Uint8List packed, int rowBytes, int height, RowFilter f) {
    final out = Uint8List((rowBytes + 1) * height);
    final prev = Uint8List(rowBytes);
    final candidate = Uint8List(rowBytes);
    for (var y = 0; y < height; y++) {
      final row = Uint8List.sublistView(packed, y * rowBytes, (y + 1) * rowBytes);
      final dst = y * (rowBytes + 1);
      int type;
      if (f == RowFilter.minSum) {
        // Sum of absolute (signed) values: the libpng heuristic.
        var bestSum = -1;
        type = 0;
        for (var t = 0; t < 5; t++) {
          _apply(t, row, prev, candidate);
          var sum = 0;
          for (final v in candidate) {
            sum += v < 128 ? v : 256 - v;
          }
          if (bestSum < 0 || sum < bestSum) {
            bestSum = sum;
            type = t;
          }
        }
      } else {
        type = f.index;
      }
      _apply(type, row, prev, candidate);
      out[dst] = type;
      out.setRange(dst + 1, dst + 1 + rowBytes, candidate);
      prev.setAll(0, row);
    }
    return out;
  }

  static void _apply(int type, Uint8List row, Uint8List prev, Uint8List out) {
    for (var i = 0; i < row.length; i++) {
      final a = i > 0 ? row[i - 1] : 0, b = prev[i], c = i > 0 ? prev[i - 1] : 0;
      out[i] = switch (type) {
        0 => row[i],
        1 => row[i] - a,
        2 => row[i] - b,
        3 => row[i] - ((a + b) >> 1),
        _ => row[i] - _paeth(a, b, c),
      } & 0xFF;
    }
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    return pb <= pc ? b : c;
  }

  static void _chunk(BytesBuilder b, String type, Uint8List data) {
    final head = ByteData(8)..setUint32(0, data.length);
    for (var i = 0; i < 4; i++) {
      head.setUint8(4 + i, type.codeUnitAt(i));
    }
    b.add(head.buffer.asUint8List());
    b.add(data);
    final crc = _crc32(head.buffer.asUint8List(4, 4), data);
    b.add((ByteData(4)..setUint32(0, crc)).buffer.asUint8List());
  }

  static final _crcTable = () {
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

  static int _crc32(Uint8List type, Uint8List data) {
    var c = 0xFFFFFFFF;
    for (final v in type) {
      c = _crcTable[(c ^ v) & 0xFF] ^ (c >>> 8);
    }
    for (final v in data) {
      c = _crcTable[(c ^ v) & 0xFF] ^ (c >>> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
