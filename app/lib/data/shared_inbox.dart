import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Photos shared to the app from another app's share sheet. The platform side
/// copies each share into a folder of its own inside an inbox folder, named so
/// they sort oldest first, with each photo named `<nnn>-<original name>` in the
/// order it was shared (Android: MainActivity.kt; iOS: the ShareExtension
/// target, through the app group). [take] reads them and removes them.
class SharedInbox {
  SharedInbox([this._channel = const MethodChannel('inkframe/share')]) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _changes.add(null);
    });
  }

  final MethodChannel _channel;
  final _changes = StreamController<void>.broadcast();

  /// A new share has finished copying (Android; iOS opens the app with inkframe://share).
  Stream<void> get changes => _changes.stream;

  /// The waiting photos as (name, bytes), oldest share first; removes them from the inbox.
  Future<List<(String, Uint8List)>> take() async {
    final path = await _channel.invokeMethod<String>('inbox');
    if (path == null) return const [];
    return takeFrom(Directory(path));
  }

  static Future<List<(String, Uint8List)>> takeFrom(Directory inbox) async {
    if (!await inbox.exists()) return const [];
    final shares = await inbox.list().where((e) => e is Directory).cast<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final photos = <(String, Uint8List)>[];
    for (final share in shares) {
      final files = await share.list().where((e) => e is File).cast<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        if (name.startsWith('.')) continue;
        photos.add((name.replaceFirst(RegExp(r'^\d+-'), ''), await f.readAsBytes()));
      }
      await share.delete(recursive: true);
    }
    return photos;
  }
}
