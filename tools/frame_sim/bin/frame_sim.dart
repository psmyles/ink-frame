// frame_sim: a command-line stand-in for an Ink Frame (PLAN.md §11 Phase 1B step 7).
//
//   dart run bin/frame_sim.dart claim --ref <project_ref> --token <pairing token>
//   dart run bin/frame_sim.dart sync [--force] [--battery 15]
//   dart run bin/frame_sim.dart status
//   dart run bin/frame_sim.dart render [--out current.png] [--prev]
//   dart run bin/frame_sim.dart reset
//
// Global: --state <dir> (default .frame_sim) holds config.json and the cache.

import 'dart:io';

import 'package:args/args.dart';
import 'package:frame_sim/frame_sim.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('state', defaultsTo: '.frame_sim', help: 'State directory (config and cache).')
    ..addFlag('help', abbr: 'h', negatable: false);
  parser.addCommand('claim')
    ..addOption('token', help: 'Pairing token from the app (or app-api /pairing-tokens).', mandatory: true)
    ..addOption('ref', help: 'Project ref; sets the API URL to https://<ref>.supabase.co/functions/v1.')
    ..addOption('api', help: 'API base URL, if not using --ref.')
    ..addOption('model', help: 'Model id (default reterminal-e1002).');
  parser.addCommand('sync')
    ..addFlag('force', negatable: false, help: 'Ask for the full manifest.')
    ..addOption('battery', help: 'Battery level to report from now on (default 100).');
  parser.addCommand('status');
  parser.addCommand('render')
    ..addOption('out', help: 'Where to copy the image (default <state>/current.png).')
    ..addFlag('prev', negatable: false, help: 'Previous image (sequential order).');
  parser.addCommand('reset');

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    _usage(parser, e.message);
  }
  final cmd = args.command;
  if (args.flag('help') || cmd == null) _usage(parser);

  final frame = Frame(Directory(args.option('state')!));
  try {
    await frame.load();
    switch (cmd.name) {
      case 'claim':
        final ref = cmd.option('ref');
        final api = cmd.option('api') ?? (ref != null ? 'https://$ref.supabase.co/functions/v1' : null);
        if (api == null) _usage(parser, 'claim needs --ref or --api');
        final id = await frame.claim(apiBaseUrl: api, pairingToken: cmd.option('token')!, modelId: cmd.option('model'));
        stdout.writeln('claimed frame $id (hw_id ${frame.config['hw_id']})');
      case 'sync':
        final battery = cmd.option('battery');
        if (battery != null) {
          frame.config['battery_pct'] = int.parse(battery).clamp(0, 100);
          await frame.save();
        }
        final r = await frame.sync(force: cmd.flag('force'));
        if (!r.manifestChanged) {
          stdout.writeln('manifest ${r.manifestVersion} unchanged; ${r.total} images cached');
        } else {
          stdout.writeln('manifest ${r.manifestVersion}: ${r.total} images '
              '(+${r.added.length} -${r.removed.length}${r.failed.isEmpty ? '' : ', ${r.failed.length} failed'})');
          for (final id in r.added) {
            stdout.writeln('  + $id');
          }
          for (final id in r.removed) {
            stdout.writeln('  - $id');
          }
          for (final id in r.failed) {
            stdout.writeln('  ! $id (retried next sync)');
          }
        }
        _printSettings(frame);
      case 'status':
        final images = await frame.readManifest();
        final c = frame.config;
        stdout
          ..writeln('hw_id        ${c['hw_id']}')
          ..writeln('model        ${c['model_id']}')
          ..writeln('paired       ${frame.isPaired ? 'yes, frame ${c['frame_id']}' : 'no'}')
          ..writeln('api          ${c['api_base_url'] ?? '-'}')
          ..writeln('manifest     ${c['manifest_version'] ?? '-'}')
          ..writeln('last sync    ${c['last_sync_at'] ?? 'never'}')
          ..writeln('cached       ${images.length} images');
        for (final i in images) {
          stdout.writeln('  ${i.position.toStringAsFixed(3).padLeft(9)}  ${i.id}  ${i.bytes} B');
        }
        _printSettings(frame);
      case 'render':
        final pick = await frame.pickNext(previous: cmd.flag('prev'));
        if (pick == null) {
          stdout.writeln(frame.isPaired
              ? 'Ready. Add photos in the Ink Frame app.'
              : 'Not paired. Hold the green button for 3 s to set up.');
          break;
        }
        final out = File(cmd.option('out') ?? '${frame.dir.path}/current.png');
        await frame.imageFile(pick.id).copy(out.path);
        final images = await frame.readManifest();
        final index = images.indexWhere((i) => i.id == pick.id) + 1;
        stdout.writeln('showing ${pick.id} ($index of ${images.length}) → ${out.path}');
      case 'reset':
        if (await frame.dir.exists()) await frame.dir.delete(recursive: true);
        stdout.writeln('factory reset: removed ${frame.dir.path}');
    }
  } on ApiException catch (e) {
    if (e.status == 410) {
      stderr.writeln('This frame was removed. Hold the green button for 3 s to set it up again. (cache wiped)');
    } else {
      stderr.writeln('error: $e');
    }
    exitCode = 1;
  } on StateError catch (e) {
    stderr.writeln('error: ${e.message}');
    exitCode = 1;
  } finally {
    frame.close();
  }
}

void _printSettings(Frame frame) {
  final s = frame.config['settings'] as Map<String, dynamic>?;
  if (s == null) return;
  final quiet = s['quiet_start'] == null ? 'off' : '${s['quiet_start']}–${s['quiet_end']}';
  stdout.writeln('settings     every ${s['image_interval_s']} s, ${s['display_order']}, '
      'sync every ${s['sync_interval_s']} s, quiet $quiet, TZ ${s['tz_posix']}');
}

Never _usage(ArgParser parser, [String? error]) {
  if (error != null) stderr.writeln('error: $error\n');
  stderr
    ..writeln('frame_sim <command> [options]')
    ..writeln('commands: claim, sync, status, render, reset')
    ..writeln(parser.usage);
  for (final c in parser.commands.entries) {
    stderr.writeln('\n${c.key}:\n${c.value.usage}');
  }
  exit(error == null ? 0 : 64);
}
