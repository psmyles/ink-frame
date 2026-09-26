import '../config/app_config.dart';

/// A frame's address: its Supabase project URL and publishable key. Not secret.
class FrameAddress {
  const FrameAddress(this.url, this.key);

  final String url;
  final String key;

  /// The project ref, e.g. `vrhsxzedzhvujnirsuhg`.
  String get ref => Uri.parse(url).host.split('.').first;

  Map<String, String> toJson() => {'url': url, 'key': key};
  static FrameAddress fromJson(Map<String, dynamic> j) => FrameAddress(j['url'] as String, j['key'] as String);

  @override
  bool operator ==(Object other) => other is FrameAddress && other.url == url && other.key == key;
  @override
  int get hashCode => Object.hash(url, key);
}

/// An invite link (one frame + code) or a "Use on another device" link (frames, no code).
///
/// Formats (same rules as central/site/assets/links.js):
/// - `https://<pages>/join#u=<project_url>&k=<publishable_key>[&c=<code>]`
/// - `inkframe://join?u=...&k=...[&c=...]`
///
/// u/k repeat once per frame; a code only comes with a single frame.
class FrameLink {
  const FrameLink(this.frames, [this.code]);

  final List<FrameAddress> frames;
  final String? code;

  bool get isInvite => code != null;

  static final _projectUrl = RegExp(r'^https://[a-z0-9]{20}\.supabase\.co$');
  static final _key = RegExp(r'^(sb_publishable_[A-Za-z0-9_-]{10,100}|eyJ[A-Za-z0-9_.-]{20,2000})$');
  static final _code = RegExp(r'^[A-Za-z0-9-]{6,64}$');
  static const _maxFrames = 20;

  /// Parses a pasted or opened link; null when it isn't a valid Ink Frame link.
  static FrameLink? parse(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final String params;
    if (uri.scheme == 'inkframe' && uri.host == 'join') {
      params = uri.query;
    } else if (uri.scheme == 'https' && (uri.path.endsWith('/join') || uri.path.endsWith('/join/'))) {
      params = uri.fragment;
    } else {
      return null;
    }
    return _fromParams(params);
  }

  static FrameLink? _fromParams(String params) {
    final pairs = <MapEntry<String, String>>[];
    for (final part in params.split('&')) {
      if (part.isEmpty) continue;
      final i = part.indexOf('=');
      if (i < 0) return null;
      try {
        pairs.add(MapEntry(
          Uri.decodeQueryComponent(part.substring(0, i)),
          Uri.decodeQueryComponent(part.substring(i + 1)),
        ));
      } on ArgumentError {
        return null;
      }
    }
    List<String> all(String k) => [for (final p in pairs) if (p.key == k) p.value];
    final urls = all('u'), keys = all('k'), codes = all('c');
    if (urls.isEmpty || urls.length != keys.length || urls.length > _maxFrames) return null;
    if (codes.length > 1 || (codes.length == 1 && urls.length != 1)) return null;

    final frames = [
      for (var i = 0; i < urls.length; i++)
        FrameAddress(urls[i].endsWith('/') ? urls[i].substring(0, urls[i].length - 1) : urls[i], keys[i]),
    ];
    if (!frames.every((f) => _projectUrl.hasMatch(f.url) && _key.hasMatch(f.key))) return null;
    final code = codes.isEmpty ? null : codes.single;
    if (code != null && !_code.hasMatch(code)) return null;
    return FrameLink(frames, code);
  }

  /// The shareable HTTPS form.
  String toHttps([String pagesUrl = AppConfig.pagesUrl]) => '$pagesUrl/join#${_params()}';

  String _params() {
    final e = Uri.encodeQueryComponent;
    return [
      for (final f in frames) ...['u=${e(f.url)}', 'k=${e(f.key)}'],
      if (code != null) 'c=${e(code!)}',
    ].join('&');
  }
}
