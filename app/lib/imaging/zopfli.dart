// A Dart deflate encoder after Zopfli (github.com/google/zopfli, Apache-2.0): the
// smallest zlib streams that any inflater (zlib, PNGdec) reads, at the cost of
// time. Used for the frame's PNGs, where every byte is stored and downloaded.
//
// Method, as in Zopfli:
// 1. Find, for every position, the smallest distance for every match length
//    (hash chains over the 32 KiB window).
// 2. Split the input into blocks where different statistics pay off (greedy parse,
//    recursive search of split points by estimated block size).
// 3. Per block, iterate: shortest-path parse under a bit-cost model taken from the
//    previous parse's symbol statistics; keep the best; perturb when stuck.
// 4. Write dynamic Huffman blocks with length-limited codes (package-merge) and the
//    smallest code-length encoding.

import 'dart:math' as math;
import 'dart:typed_data';

class Zopfli {
  /// Compresses [data] to a zlib stream (RFC 1950). More [iterations] can find a
  /// slightly smaller parse; 15 is Zopfli's default. [maxChain] bounds the match
  /// search: on dithered 800×480 images 1024 is within 0.2 % of Zopfli's 8192 and
  /// about 3× faster (~0.9 s vs ~3 s per image, AOT on an M-series Mac).
  static Uint8List zlib(Uint8List data, {int iterations = 15, int maxBlocks = 15, int maxChain = 1024}) {
    final deflate = _Deflater(data, iterations: iterations, maxBlocks: maxBlocks, maxChain: maxChain).run();
    final out = Uint8List(2 + deflate.length + 4);
    out[0] = 0x78;
    out[1] = 0xDA; // 32 KiB window, maximum compression
    out.setRange(2, 2 + deflate.length, deflate);
    final a = _adler32(data);
    out.buffer.asByteData().setUint32(out.length - 4, a);
    return out;
  }

  static int _adler32(Uint8List data) {
    var a = 1, b = 0;
    var i = 0;
    while (i < data.length) {
      final end = math.min(i + 5552, data.length);
      for (; i < end; i++) {
        a += data[i];
        b += a;
      }
      a %= 65521;
      b %= 65521;
    }
    return (b << 16) | a;
  }
}

// ── Deflate tables ────────────────────────────────────────────────────────────

const _lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
const _lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
const _distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
const _distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
const _clOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

const _minMatch = 3, _maxMatch = 258, _window = 32768;

/// Length (3..258) → symbol (257..285), extra bit count and value.
final _lenSym = Int32List(259), _lenXBits = Int32List(259), _lenXVal = Int32List(259);

/// Distance (1..32768) → symbol (0..29).
final _distSym = Uint8List(_window + 1);

bool _tablesReady = false;

void _initTables() {
  if (_tablesReady) return;
  for (var s = 0; s < 29; s++) {
    final hi = s == 28 ? 258 : (s == 27 ? 257 : _lengthBase[s + 1] - 1);
    for (var l = _lengthBase[s]; l <= hi; l++) {
      _lenSym[l] = 257 + s;
      _lenXBits[l] = _lengthExtra[s];
      _lenXVal[l] = l - _lengthBase[s];
    }
  }
  // Length 258 has its own symbol (285); 227..257 use 284.
  for (var l = 227; l <= 257; l++) {
    _lenSym[l] = 284;
    _lenXBits[l] = 5;
    _lenXVal[l] = l - 227;
  }
  _lenSym[258] = 285;
  _lenXBits[258] = 0;
  _lenXVal[258] = 0;
  for (var s = 0; s < 30; s++) {
    final hi = s == 29 ? _window : _distBase[s + 1] - 1;
    for (var d = _distBase[s]; d <= hi; d++) {
      _distSym[d] = s;
    }
  }
  _tablesReady = true;
}

// ── LZ77 symbols ──────────────────────────────────────────────────────────────

/// A parse: `litLen` is a literal byte (dist 0) or a match length (dist > 0); `pos`
/// is where each symbol starts in the input.
class _Store {
  final litLen = <int>[];
  final dist = <int>[];
  final pos = <int>[];

  int get length => litLen.length;

  void add(int ll, int d, int p) {
    litLen.add(ll);
    dist.add(d);
    pos.add(p);
  }

  void addAll(_Store o, [int from = 0, int? to]) {
    litLen.addAll(o.litLen.sublist(from, to));
    dist.addAll(o.dist.sublist(from, to));
    pos.addAll(o.pos.sublist(from, to));
  }

  /// Histograms of symbols [from, to): 288 lit/len (256 = end of block) and 32 dist.
  (Int32List, Int32List) histogram(int from, int to) {
    final ll = Int32List(288), d = Int32List(32);
    for (var i = from; i < to; i++) {
      if (dist[i] == 0) {
        ll[litLen[i]]++;
      } else {
        ll[_lenSym[litLen[i]]]++;
        d[_distSym[dist[i]]]++;
      }
    }
    ll[256] = 1;
    return (ll, d);
  }
}

// ── Match finder ──────────────────────────────────────────────────────────────

/// For each position, the (length, distance) breakpoints: walking the chain from the
/// nearest candidate, each entry is a new longest length with its (smallest)
/// distance. For a length L the best distance is that of the first entry ≥ L.
class _Matches {
  _Matches(Uint8List data, int maxChain) : start = Int32List(data.length + 1) {
    final n = data.length;
    const hashBits = 16, hashSize = 1 << hashBits;
    final head = Int32List(hashSize)..fillRange(0, hashSize, -1);
    final prev = Int32List(n);
    final lens = <int>[], dists = <int>[];
    int hashAt(int i) => (((data[i] << 16) | (data[i + 1] << 8) | data[i + 2]) * 2654435761 >> 16) & (hashSize - 1);

    for (var i = 0; i < n; i++) {
      start[i] = lens.length;
      if (i + _minMatch > n) continue;
      final h = hashAt(i);
      final limit = math.min(_maxMatch, n - i);
      var best = _minMatch - 1;
      var cand = head[h];
      var chain = 0;
      while (cand >= 0 && chain < maxChain) {
        final d = i - cand;
        if (d > _window) break;
        chain++;
        // Quick reject: must beat the current best at its last byte.
        if (data[cand + best] == data[i + best] || best < _minMatch) {
          var l = 0;
          while (l < limit && data[cand + l] == data[i + l]) {
            l++;
          }
          if (l > best && l >= _minMatch) {
            best = l;
            lens.add(l);
            dists.add(d);
            if (l == limit) break;
          }
        }
        cand = prev[cand];
      }
      prev[i] = head[h];
      head[h] = i;
    }
    start[n] = lens.length;
    this.lens = Int32List.fromList(lens);
    this.dists = Int32List.fromList(dists);
  }

  final Int32List start;
  late final Int32List lens;
  late final Int32List dists;

  /// The longest match at [i], as (length, distance), or (0, 0).
  (int, int) longest(int i) {
    final e = start[i + 1];
    return e == start[i] ? (0, 0) : (lens[e - 1], dists[e - 1]);
  }

  /// Smallest distance for a match of exactly [len] at [i].
  int distFor(int i, int len) {
    for (var k = start[i]; k < start[i + 1]; k++) {
      if (lens[k] >= len) return dists[k];
    }
    throw StateError('no match of $len at $i');
  }
}

// ── Huffman ───────────────────────────────────────────────────────────────────

/// Code lengths ≤ [maxBits] minimising the total cost (package-merge).
Int32List _codeLengths(Int32List freqs, int maxBits) {
  final n = freqs.length;
  final out = Int32List(n);
  final leaves = [for (var i = 0; i < n; i++) if (freqs[i] > 0) i]..sort((a, b) {
      final c = freqs[a].compareTo(freqs[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  if (leaves.isEmpty) return out;
  if (leaves.length == 1) {
    out[leaves.single] = 1;
    return out;
  }
  // Items: weight + either a leaf index or two child items.
  final leafItems = [for (final s in leaves) _Item(freqs[s], s, null, null)];
  var list = leafItems;
  for (var level = 1; level < maxBits; level++) {
    final packages = <_Item>[];
    for (var i = 0; i + 1 < list.length; i += 2) {
      packages.add(_Item(list[i].weight + list[i + 1].weight, -1, list[i], list[i + 1]));
    }
    final merged = <_Item>[];
    var a = 0, b = 0;
    while (a < leafItems.length || b < packages.length) {
      if (b >= packages.length || (a < leafItems.length && leafItems[a].weight <= packages[b].weight)) {
        merged.add(leafItems[a++]);
      } else {
        merged.add(packages[b++]);
      }
    }
    list = merged;
  }
  final take = 2 * leaves.length - 2;
  final stack = <_Item>[...list.take(take)];
  while (stack.isNotEmpty) {
    final it = stack.removeLast();
    if (it.leaf >= 0) {
      out[it.leaf]++;
    } else {
      stack
        ..add(it.left!)
        ..add(it.right!);
    }
  }
  return out;
}

class _Item {
  _Item(this.weight, this.leaf, this.left, this.right);

  final int weight;
  final int leaf;
  final _Item? left, right;
}

/// Canonical codes (RFC 1951 §3.2.2), bit-reversed for LSB-first writing.
Int32List _codes(Int32List lengths) {
  const maxBits = 16;
  final blCount = Int32List(maxBits);
  for (final l in lengths) {
    if (l > 0) blCount[l]++;
  }
  final next = Int32List(maxBits);
  var code = 0;
  for (var bits = 1; bits < maxBits; bits++) {
    code = (code + blCount[bits - 1]) << 1;
    next[bits] = code;
  }
  final out = Int32List(lengths.length);
  for (var s = 0; s < lengths.length; s++) {
    final l = lengths[s];
    if (l == 0) continue;
    var c = next[l]++;
    var r = 0;
    for (var k = 0; k < l; k++) {
      r = (r << 1) | (c & 1);
      c >>= 1;
    }
    out[s] = r;
  }
  return out;
}

/// Zlib and old inflaters want at least two distance codes.
void _patchDistanceCodes(Int32List dLengths) {
  var used = 0;
  for (final l in dLengths) {
    if (l > 0) used++;
  }
  if (used >= 2) return;
  if (used == 0) {
    dLengths[0] = 1;
    dLengths[1] = 1;
  } else {
    dLengths[dLengths[0] > 0 ? 1 : 0] = 1;
  }
}

// ── Bit writer ────────────────────────────────────────────────────────────────

class _Bits {
  final _out = BytesBuilder(copy: false);
  final _buf = Uint8List(1 << 16);
  var _n = 0;
  var _acc = 0;
  var _accBits = 0;

  void write(int value, int bits) {
    _acc |= value << _accBits;
    _accBits += bits;
    while (_accBits >= 8) {
      _byte(_acc & 0xFF);
      _acc >>= 8;
      _accBits -= 8;
    }
  }

  void _byte(int b) {
    _buf[_n++] = b;
    if (_n == _buf.length) {
      _out.add(Uint8List.fromList(_buf));
      _n = 0;
    }
  }

  Uint8List finish() {
    if (_accBits > 0) _byte(_acc & 0xFF);
    _out.add(Uint8List.sublistView(_buf, 0, _n));
    return _out.toBytes();
  }
}

// ── Tree header ───────────────────────────────────────────────────────────────

/// The run-length coded code-length sequence (symbols 0..18 + extra bits) for one
/// choice of which RLE codes to use.
class _TreeEncoding {
  _TreeEncoding(this.hlit, this.hdist, this.symbols, this.extras, this.clLengths, this.hclen, this.bits);

  final int hlit, hdist, hclen, bits;
  final List<int> symbols, extras;
  final Int32List clLengths;
}

_TreeEncoding _encodeTree(Int32List ll, Int32List d) {
  var hlit = 286, hdist = 30;
  while (hlit > 257 && ll[hlit - 1] == 0) {
    hlit--;
  }
  while (hdist > 1 && d[hdist - 1] == 0) {
    hdist--;
  }
  final seq = [for (var i = 0; i < hlit; i++) ll[i], for (var i = 0; i < hdist; i++) d[i]];

  _TreeEncoding? best;
  for (var variant = 0; variant < 8; variant++) {
    final use16 = variant & 1 != 0, use17 = variant & 2 != 0, use18 = variant & 4 != 0;
    final syms = <int>[], extras = <int>[];
    for (var i = 0; i < seq.length; i++) {
      final symbol = seq[i];
      var count = 1;
      if (use16 || (symbol == 0 && (use17 || use18))) {
        for (var j = i + 1; j < seq.length && seq[j] == symbol; j++) {
          count++;
        }
      }
      i += count - 1;
      if (symbol == 0 && count >= 3) {
        if (use18) {
          while (count >= 11) {
            final c = math.min(count, 138);
            syms.add(18);
            extras.add(c - 11);
            count -= c;
          }
        }
        if (use17) {
          while (count >= 3) {
            final c = math.min(count, 10);
            syms.add(17);
            extras.add(c - 3);
            count -= c;
          }
        }
      }
      if (use16 && count >= 4) {
        count--;
        syms.add(symbol);
        extras.add(0);
        while (count >= 3) {
          final c = math.min(count, 6);
          syms.add(16);
          extras.add(c - 3);
          count -= c;
        }
      }
      for (; count > 0; count--) {
        syms.add(symbol);
        extras.add(0);
      }
    }
    final clFreq = Int32List(19);
    for (final s in syms) {
      clFreq[s]++;
    }
    final clLengths = _codeLengths(clFreq, 7);
    var hclen = 19;
    while (hclen > 4 && clLengths[_clOrder[hclen - 1]] == 0) {
      hclen--;
    }
    var bits = 14 + hclen * 3;
    for (var k = 0; k < syms.length; k++) {
      final s = syms[k];
      bits += clLengths[s] + (s == 16 ? 2 : (s == 17 ? 3 : (s == 18 ? 7 : 0)));
    }
    if (best == null || bits < best.bits) best = _TreeEncoding(hlit, hdist, syms, extras, clLengths, hclen, bits);
  }
  return best!;
}

// ── Deflater ──────────────────────────────────────────────────────────────────

class _Deflater {
  _Deflater(this.data, {required this.iterations, required this.maxBlocks, required int maxChain}) {
    _initTables();
    matches = _Matches(data, maxChain);
  }

  final Uint8List data;
  final int iterations;
  final int maxBlocks;
  late final _Matches matches;

  Uint8List run() {
    final n = data.length;
    final bits = _Bits();
    if (n == 0) {
      // A single empty fixed block: BFINAL=1, BTYPE=01, end-of-block (7 zero bits).
      bits.write(1, 1);
      bits.write(1, 2);
      bits.write(0, 7);
      return bits.finish();
    }

    // Split points from a greedy parse, then optimise each block.
    final greedy = _greedy(0, n);
    final splitsLz = _blockSplit(greedy);
    final bounds = [0, for (final s in splitsLz) greedy.pos[s], n];

    final all = _Store();
    final starts = <int>[];
    var total = 0.0;
    for (var b = 0; b + 1 < bounds.length; b++) {
      starts.add(all.length);
      final store = _optimal(bounds[b], bounds[b + 1]);
      total += _blockBits(store, 0, store.length);
      all.addAll(store);
    }

    // A second split on the final parse sometimes does better.
    var blockStarts = starts;
    if (starts.length > 1) {
      final again = _blockSplit(all);
      final alt = [0, ...again];
      var altTotal = 0.0;
      for (var b = 0; b < alt.length; b++) {
        altTotal += _blockBits(all, alt[b], b + 1 < alt.length ? alt[b + 1] : all.length);
      }
      if (altTotal < total) blockStarts = alt;
    }

    for (var b = 0; b < blockStarts.length; b++) {
      final end = b + 1 < blockStarts.length ? blockStarts[b + 1] : all.length;
      _writeBlock(bits, all, blockStarts[b], end, b == blockStarts.length - 1);
    }
    return bits.finish();
  }

  /// Greedy parse with one-step lazy matching, for statistics and splitting.
  _Store _greedy(int from, int to) {
    final s = _Store();
    var i = from;
    while (i < to) {
      var (len, dist) = matches.longest(i);
      len = math.min(len, to - i);
      if (len >= _minMatch && i + 1 < to) {
        final (nextLen, _) = matches.longest(i + 1);
        if (math.min(nextLen, to - i - 1) > len) {
          s.add(data[i], 0, i);
          i++;
          continue;
        }
      }
      if (len >= _minMatch) {
        s.add(len, len == matches.longest(i).$1 ? dist : matches.distFor(i, len), i);
        i += len;
      } else {
        s.add(data[i], 0, i);
        i++;
      }
    }
    return s;
  }

  /// Estimated bits of one dynamic block holding symbols [from, to).
  double _blockBits(_Store s, int from, int to) {
    final (llFreq, dFreq) = s.histogram(from, to);
    final ll = _codeLengths(llFreq, 15), d = _codeLengths(dFreq, 15);
    _patchDistanceCodes(d);
    var bits = 3 + _encodeTree(ll, d).bits;
    for (var i = 0; i < 288; i++) {
      if (llFreq[i] == 0) continue;
      bits += llFreq[i] * ll[i];
      if (i > 256) bits += llFreq[i] * _lengthExtra[i - 257];
    }
    for (var i = 0; i < 30; i++) {
      bits += dFreq[i] * (d[i] + _distExtra[i]);
    }
    return bits.toDouble();
  }

  /// Zopfli's block splitting: symbol indices where new blocks start.
  List<int> _blockSplit(_Store s) {
    final points = <int>[];
    if (s.length < 10 || maxBlocks <= 1) return points;
    final done = <int>{};
    var lstart = 0, lend = s.length;
    var blocks = 1;
    while (true) {
      if (blocks >= maxBlocks) break;
      final (llpos, splitCost) = _findMinimum(
        (i) => _blockBits(s, lstart, i) + _blockBits(s, i, lend),
        lstart + 1,
        lend,
      );
      final origCost = _blockBits(s, lstart, lend);
      if (splitCost > origCost || llpos == lstart + 1 || llpos == lend) {
        done.add(lstart);
      } else {
        points
          ..add(llpos)
          ..sort();
        blocks++;
      }
      // The largest block not yet done.
      var bestSize = 0;
      final starts = [0, ...points], ends = [...points, s.length];
      for (var k = 0; k < starts.length; k++) {
        if (done.contains(starts[k])) continue;
        if (ends[k] - starts[k] > bestSize) {
          bestSize = ends[k] - starts[k];
          lstart = starts[k];
          lend = ends[k];
        }
      }
      if (bestSize < 10) break;
    }
    return points;
  }

  static (int, double) _findMinimum(double Function(int) f, int start, int end) {
    if (end - start < 1024) {
      var best = double.infinity;
      var bestI = start;
      for (var i = start; i < end; i++) {
        final v = f(i);
        if (v < best) {
          best = v;
          bestI = i;
        }
      }
      return (bestI, best);
    }
    const num = 9;
    var lastBest = double.infinity;
    var pos = start;
    while (end - start > num) {
      final p = List<int>.generate(num, (i) => start + (i + 1) * ((end - start) ~/ (num + 1)));
      final vp = [for (final x in p) f(x)];
      var besti = 0;
      for (var i = 1; i < num; i++) {
        if (vp[i] < vp[besti]) besti = i;
      }
      if (vp[besti] > lastBest) break;
      start = besti == 0 ? start : p[besti - 1];
      end = besti == num - 1 ? end : p[besti + 1];
      pos = p[besti];
      lastBest = vp[besti];
    }
    return (pos, lastBest);
  }

  /// Iterated shortest-path parse of [from, to) (Zopfli's LZ77Optimal).
  _Store _optimal(int from, int to) {
    final len = to - from;
    final costs = Float64List(len + 1);
    final lengthTo = Int32List(len + 1);
    final rng = _Ran();

    var stats = _Stats.from(_greedy(from, to));
    _Stats? lastStats;
    _Stats bestStats = stats;
    _Store? best;
    var bestCost = double.infinity, lastCost = -1.0;
    var lastRandomStep = -1;

    for (var it = 0; it < iterations; it++) {
      final store = _shortestPath(from, to, stats, costs, lengthTo);
      final cost = _blockBits(store, 0, store.length);
      if (cost < bestCost) {
        best = store;
        bestCost = cost;
        bestStats = stats;
      }
      lastStats = stats;
      stats = _Stats.from(store);
      if (lastRandomStep != -1) stats = stats.blend(lastStats, 0.5);
      if (it > 5 && cost == lastCost) {
        stats = bestStats.randomized(rng);
        lastRandomStep = it;
      }
      lastCost = cost;
    }
    return best!;
  }

  _Store _shortestPath(int from, int to, _Stats stats, Float64List costs, Int32List lengthTo) {
    final len = to - from;
    final litCost = stats.llBits;
    final lenCost = Float64List(259);
    for (var l = _minMatch; l <= _maxMatch; l++) {
      lenCost[l] = litCost[_lenSym[l]] + _lenXBits[l];
    }
    final distCost = Float64List(30);
    for (var s = 0; s < 30; s++) {
      distCost[s] = stats.dBits[s] + _distExtra[s];
    }

    costs.fillRange(1, len + 1, double.infinity);
    costs[0] = 0;
    final mStart = matches.start, mLens = matches.lens, mDists = matches.dists;
    for (var i = 0; i < len; i++) {
      final base = costs[i];
      final p = from + i;
      final lit = base + litCost[data[p]];
      if (lit < costs[i + 1]) {
        costs[i + 1] = lit;
        lengthTo[i + 1] = 1;
      }
      final maxL = to - p;
      var prevLen = _minMatch - 1;
      for (var k = mStart[p]; k < mStart[p + 1] && prevLen < maxL; k++) {
        final dc = distCost[_distSym[mDists[k]]];
        final upTo = math.min(mLens[k], maxL);
        for (var l = prevLen + 1; l <= upTo; l++) {
          final c = base + lenCost[l] + dc;
          if (c < costs[i + l]) {
            costs[i + l] = c;
            lengthTo[i + l] = l;
          }
        }
        prevLen = upTo;
      }
    }

    // Trace back and emit.
    final path = <int>[];
    for (var i = len; i > 0; i -= lengthTo[i]) {
      path.add(lengthTo[i]);
    }
    final s = _Store();
    var p = from;
    for (var k = path.length - 1; k >= 0; k--) {
      final l = path[k];
      if (l == 1) {
        s.add(data[p], 0, p);
      } else {
        s.add(l, matches.distFor(p, l), p);
      }
      p += l;
    }
    return s;
  }

  void _writeBlock(_Bits out, _Store s, int from, int to, bool last) {
    final (llFreq, dFreq) = s.histogram(from, to);
    final ll = _codeLengths(llFreq, 15), d = _codeLengths(dFreq, 15);
    _patchDistanceCodes(d);
    final tree = _encodeTree(ll, d);

    out.write(last ? 1 : 0, 1);
    out.write(2, 2); // dynamic Huffman
    out.write(tree.hlit - 257, 5);
    out.write(tree.hdist - 1, 5);
    out.write(tree.hclen - 4, 4);
    for (var k = 0; k < tree.hclen; k++) {
      out.write(tree.clLengths[_clOrder[k]], 3);
    }
    final clCodes = _codes(tree.clLengths);
    for (var k = 0; k < tree.symbols.length; k++) {
      final sym = tree.symbols[k];
      out.write(clCodes[sym], tree.clLengths[sym]);
      if (sym == 16) out.write(tree.extras[k], 2);
      if (sym == 17) out.write(tree.extras[k], 3);
      if (sym == 18) out.write(tree.extras[k], 7);
    }

    final llCodes = _codes(ll), dCodes = _codes(d);
    for (var i = from; i < to; i++) {
      final dist = s.dist[i];
      if (dist == 0) {
        final c = s.litLen[i];
        out.write(llCodes[c], ll[c]);
      } else {
        final l = s.litLen[i];
        final sym = _lenSym[l];
        out.write(llCodes[sym], ll[sym]);
        if (_lenXBits[l] > 0) out.write(_lenXVal[l], _lenXBits[l]);
        final ds = _distSym[dist];
        out.write(dCodes[ds], d[ds]);
        if (_distExtra[ds] > 0) out.write(dist - _distBase[ds], _distExtra[ds]);
      }
    }
    out.write(llCodes[256], ll[256]);
  }
}

/// Symbol statistics and the bit costs derived from them.
class _Stats {
  _Stats(this.llFreq, this.dFreq) {
    llBits = _entropy(llFreq);
    dBits = _entropy(dFreq);
  }

  factory _Stats.from(_Store s) {
    final (ll, d) = s.histogram(0, s.length);
    return _Stats(Float64List.fromList([for (final v in ll) v.toDouble()]), Float64List.fromList([for (final v in d) v.toDouble()]));
  }

  final Float64List llFreq, dFreq;
  late final Float64List llBits, dBits;

  static Float64List _entropy(Float64List f) {
    var sum = 0.0;
    for (final v in f) {
      sum += v;
    }
    final log2sum = math.log(sum == 0 ? f.length.toDouble() : sum) / math.ln2;
    final out = Float64List(f.length);
    for (var i = 0; i < f.length; i++) {
      out[i] = f[i] == 0 ? log2sum : log2sum - math.log(f[i]) / math.ln2;
      if (out[i] < 0) out[i] = 0;
    }
    return out;
  }

  _Stats blend(_Stats other, double w) => _Stats(
        Float64List.fromList([for (var i = 0; i < llFreq.length; i++) llFreq[i] + other.llFreq[i] * w]),
        Float64List.fromList([for (var i = 0; i < dFreq.length; i++) dFreq[i] + other.dFreq[i] * w]),
      )..llFreq[256] = 1;

  _Stats randomized(_Ran r) {
    Float64List rand(Float64List f) {
      final o = Float64List.fromList(f);
      for (var i = 0; i < o.length; i++) {
        if ((r.next() >> 4) % 3 == 0) o[i] = o[r.next() % o.length];
      }
      return o;
    }

    final ll = rand(llFreq)..[256] = 1;
    return _Stats(ll, rand(dFreq));
  }
}

/// Zopfli's multiply-with-carry generator, for repeatable runs.
class _Ran {
  int _w = 1, _z = 2;

  int next() {
    _z = (36969 * (_z & 65535) + (_z >> 16)) & 0xFFFFFFFF;
    _w = (18000 * (_w & 65535) + (_w >> 16)) & 0xFFFFFFFF;
    return ((_z << 16) + _w) & 0xFFFFFFFF;
  }
}
