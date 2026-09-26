/// A panel's palette (shared/presets.json, `public.palettes`): the calibrated
/// colours the panel really shows (dithering and preview) and the pure colours the
/// firmware expects in the PNG (index for index).
class Palette {
  Palette({required this.id, required this.colors, required this.deviceColors})
      : assert(colors.length == deviceColors.length && colors.length >= 2 && colors.length <= 16);

  final String id;

  /// Calibrated RGB, three ints per colour, for dithering and previews.
  final List<List<int>> colors;

  /// Device RGB (`deviceColor`), written to the PNG's PLTE.
  final List<List<int>> deviceColors;

  int get length => colors.length;

  /// From a presets/DB palette: `{id, colors: [{name, color, deviceColor}]}`.
  factory Palette.fromJson(Map<String, dynamic> j) {
    final entries = (j['colors'] as List).cast<Map<String, dynamic>>();
    return Palette(
      id: j['id'] as String,
      colors: [for (final c in entries) hexToRgb(c['color'] as String)],
      deviceColors: [for (final c in entries) hexToRgb(c['deviceColor'] as String)],
    );
  }

  static List<int> hexToRgb(String hex) {
    var h = hex.startsWith('#') ? hex.substring(1) : hex;
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    return [for (var i = 0; i < 6; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
  }
}
