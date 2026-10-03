// The backend the app installs into new frames (assets/backend/) matches backend/
// and shared/presets.json. If this fails, run tools/dev/bundle-backend.ts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = Directory('../backend/supabase');
  final assets = Directory('assets/backend');
  String read(Directory d, String path) => File('${d.path}/$path').readAsStringSync();
  List<String> names(Directory d, RegExp re) =>
      [for (final f in d.listSync().whereType<File>()) f.uri.pathSegments.last].where(re.hasMatch).toList()..sort();

  test('migrations, seed and functions are the same as backend/supabase', () {
    final manifest = jsonDecode(read(assets, 'manifest.json')) as Map<String, dynamic>;
    final migrations = names(Directory('${src.path}/migrations'), RegExp(r'^\d+_.+\.sql$'));
    expect([for (final m in manifest['migrations'] as List) (m as Map)['file']], [for (final n in migrations) 'migrations/$n']);
    for (final n in migrations) {
      expect(read(assets, 'migrations/$n'), read(src, 'migrations/$n'), reason: n);
    }
    expect(read(assets, 'seed.sql'), read(src, 'seed.sql'));

    final functions = manifest['functions'] as Map<String, dynamic>;
    for (final dir in ['device-api', 'app-api', '_shared']) {
      final files = names(Directory('${src.path}/functions/$dir'), RegExp(r'\.ts$'));
      expect(functions[dir], [for (final f in files) '$dir/$f'], reason: dir);
      for (final f in files) {
        expect(read(assets, 'functions/$dir/$f'), read(src, 'functions/$dir/$f'), reason: '$dir/$f');
      }
    }
  });

  test('the model list matches the seed', () {
    final models = [for (final m in jsonDecode(read(assets, 'models.json')) as List) (m as Map)['id']];
    final seeded = RegExp(r"^  \('([a-z0-9-]+)', '[^']*', \d+, \d+, '\w+'\)", multiLine: true)
        .allMatches(read(src, 'seed.sql'))
        .map((m) => m.group(1))
        .toList();
    expect(models, seeded);
    expect(models, contains('reterminal-e1002'));
  });
}
