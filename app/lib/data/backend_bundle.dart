import 'dart:convert';

import 'package:flutter/services.dart';

/// A frame model the wizard offers (from `shared/presets.json`).
class ModelOption {
  const ModelOption({required this.id, required this.name, required this.width, required this.height});

  final String id;
  final String name;
  final int width;
  final int height;

  factory ModelOption.fromJson(Map<String, dynamic> j) => ModelOption(
        id: j['id'] as String,
        name: j['name'] as String,
        width: j['width'] as int,
        height: j['height'] as int,
      );
}

class Migration {
  const Migration(this.version, this.sql);

  final int version;
  final String sql;
}

/// One Edge Function source file, at its path under `functions/`.
class SourceFile {
  const SourceFile(this.path, this.contents);

  final String path;
  final String contents;
}

/// The frame backend shipped in the app (`assets/backend/`, copied by
/// tools/dev/bundle-backend.ts): what the wizard installs into a new frame's project,
/// and what "Update" brings an older frame up to (PLAN.md §6.2–6.3).
class BackendBundle {
  const BackendBundle({
    required this.migrations,
    required this.seed,
    required this.functions,
    required this.models,
    required this.auth,
    required this.fingerprint,
  });

  final List<Migration> migrations;
  final String seed;

  /// Function slug → its files plus `_shared/`.
  final Map<String, List<SourceFile>> functions;
  final List<ModelOption> models;

  /// The Google/Apple sign-in settings every frame's project gets.
  final Map<String, Object?> auth;

  /// Identifies this backend (migrations, seed, functions); kept in each frame's
  /// `private.config` so "Update" also notices changes that need no migration.
  final String fingerprint;

  int get latestVersion => migrations.isEmpty ? 0 : migrations.last.version;

  static const _root = 'assets/backend/';

  static Future<BackendBundle> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    Future<String> read(String path) => b.loadString('$_root$path', cache: false);
    final manifest = jsonDecode(await read('manifest.json')) as Map<String, dynamic>;

    final migrations = [
      for (final m in manifest['migrations'] as List)
        Migration((m as Map<String, dynamic>)['version'] as int, await read(m['file'] as String)),
    ]..sort((a, b) => a.version.compareTo(b.version));

    final groups = (manifest['functions'] as Map<String, dynamic>).map((k, v) => MapEntry(k, [for (final p in v as List) p as String]));
    Future<List<SourceFile>> files(String group) async =>
        [for (final p in groups[group] ?? const <String>[]) SourceFile(p, await read('functions/$p'))];
    final shared = await files('_shared');
    final functions = {
      for (final slug in groups.keys.where((k) => k != '_shared')) slug: [...await files(slug), ...shared],
    };

    final models = [
      for (final m in jsonDecode(await read('models.json')) as List) ModelOption.fromJson(m as Map<String, dynamic>),
    ];
    return BackendBundle(
      migrations: migrations,
      seed: await read('seed.sql'),
      functions: functions,
      models: models,
      auth: jsonDecode(await read('auth.json')) as Map<String, dynamic>,
      fingerprint: manifest['fingerprint'] as String,
    );
  }
}
