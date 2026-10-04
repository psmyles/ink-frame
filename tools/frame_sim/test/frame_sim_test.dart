import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:frame_sim/frame_sim.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A fake device-api: serves a manifest and image bytes, records requests.
class FakeServer {
  final images = <String, List<int>>{}; // id → bytes
  final order = <String>[]; // ids by position
  int manifestVersion = 1;
  int status = 200;
  bool corruptDownloads = false;
  final syncBodies = <Map<String, dynamic>>[];

  void put(String id, String content) {
    images[id] = utf8.encode(content);
    order.add(id);
    manifestVersion++;
  }

  void remove(String id) {
    images.remove(id);
    order.remove(id);
    manifestVersion++;
  }

  MockClient get client => MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/device-api/claim')) {
          return http.Response(jsonEncode({'frame_id': 'frame-1', 'device_secret': 's' * 43}), 200);
        }
        if (path.endsWith('/device-api/sync')) {
          if (status != 200) {
            return http.Response(jsonEncode({'error': {'code': 'frame_removed', 'message': 'removed'}}), status);
          }
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          syncBodies.add(body);
          final local = (body['local_ids'] as List).cast<String>();
          return http.Response(
              jsonEncode({
                'manifest_version': manifestVersion,
                'settings': {'display_order': 'sequential', 'tz_posix': 'UTC0'},
                if (body['manifest_version'] != manifestVersion)
                  'images': [
                    for (final (i, id) in order.indexed)
                      {
                        'id': id,
                        'sha256': sha256.convert(images[id]!).toString(),
                        'bytes': images[id]!.length,
                        'position': i + 1.0,
                        if (!local.contains(id)) 'url': 'https://storage.test/$id',
                      }
                  ],
                'server_time': 0,
              }),
              200);
        }
        if (req.url.host == 'storage.test') {
          final id = req.url.pathSegments.last;
          final bytes = images[id];
          if (bytes == null) return http.Response('gone', 404);
          return http.Response.bytes(corruptDownloads ? [...bytes, 0] : bytes, 200);
        }
        return http.Response('not found', 404);
      });
}

void main() {
  late Directory dir;
  late FakeServer server;
  late Frame frame;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('frame_sim_test');
    server = FakeServer();
    frame = Frame(dir, client: server.client);
    await frame.load();
    await frame.claim(apiBaseUrl: 'https://api.test/functions/v1/', pairingToken: 'T' * 26);
  });

  tearDown(() => dir.delete(recursive: true));

  Future<List<String>> cachedFiles() async => [
        await for (final f in frame.cacheDir.list())
          if (f.path.endsWith('.png')) f.uri.pathSegments.last,
      ]..sort();

  test('claim stores the secret and a stable hw_id', () {
    expect(frame.isPaired, isTrue);
    expect(frame.config['hw_id'], startsWith('sim-'));
    expect(frame.config['api_base_url'], 'https://api.test/functions/v1');
  });

  test('first sync asks for everything and mirrors it', () async {
    server
      ..put('a', 'AAAA')
      ..put('b', 'BBBB');
    final r = await frame.sync();
    expect(server.syncBodies.single['manifest_version'], 0);
    expect(r.added, ['a', 'b']);
    expect(await cachedFiles(), ['a.png', 'b.png']);
    expect((await frame.readManifest()).map((i) => i.id), ['a', 'b']);
  });

  test('deletes are mirrored and cached ids are reported', () async {
    server
      ..put('a', 'AAAA')
      ..put('b', 'BBBB');
    await frame.sync();
    server.remove('a');
    final r = await frame.sync();
    expect(server.syncBodies.last['local_ids'], ['a', 'b']);
    expect(r.removed, ['a']);
    expect(r.added, isEmpty);
    expect(await cachedFiles(), ['b.png']);
  });

  test('unchanged manifest leaves the cache alone', () async {
    server.put('a', 'AAAA');
    await frame.sync();
    final r = await frame.sync();
    expect(r.manifestChanged, isFalse);
    expect(await cachedFiles(), ['a.png']);
  });

  test('a bad download is not kept and the manifest version does not advance', () async {
    server.put('a', 'AAAA');
    server.corruptDownloads = true;
    final r = await frame.sync();
    expect(r.failed, ['a']);
    expect(await cachedFiles(), isEmpty);
    expect(Directory('${frame.cacheDir.path}/tmp').listSync(), isEmpty, reason: 'nothing half-written');

    server.corruptDownloads = false;
    final retry = await frame.sync();
    expect(server.syncBodies.last['manifest_version'], isNot(server.manifestVersion));
    expect(retry.added, ['a']);
  });

  test('410 wipes the cache and the secret', () async {
    server.put('a', 'AAAA');
    await frame.sync();
    server.status = 410;
    await expectLater(frame.sync(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 410)));
    expect(frame.isPaired, isFalse);
    expect(await cachedFiles(), isEmpty);
  });

  test('pickNext: new arrivals first, then sequential with prev', () async {
    server
      ..put('a', 'AAAA')
      ..put('b', 'BBBB')
      ..put('c', 'CCCC');
    await frame.sync();
    // Newest arrivals first (last added first), then the sequential cycle.
    final seen = [for (var i = 0; i < 3; i++) (await frame.pickNext())!.id];
    expect(seen, ['c', 'b', 'a']);
    expect((await frame.pickNext())!.id, 'a');
    expect((await frame.pickNext())!.id, 'b');
    expect((await frame.pickNext(previous: true))!.id, 'a');
    expect((await frame.pickNext(previous: true))!.id, 'c', reason: 'wraps around');
  });

  test('pickNext random never repeats the last image', () async {
    server
      ..put('a', 'AAAA')
      ..put('b', 'BBBB');
    await frame.sync();
    frame.config['newest_first'] = [];
    frame.config['settings'] = {'display_order': 'random'};
    final rng = Random(1);
    var last = (await frame.pickNext(random: rng))!.id;
    for (var i = 0; i < 20; i++) {
      final next = (await frame.pickNext(random: rng))!.id;
      expect(next, isNot(last));
      last = next;
    }
  });

  test('reports its memory card: size, free space and what its photos take', () async {
    await frame.setCard('ok', totalBytes: 1000, otherBytes: 100);
    server.put('a', 'AAAA');
    await frame.sync();
    await frame.sync();
    final body = server.syncBodies.last;
    expect(body['sd_total_bytes'], 1000);
    expect(body['cache_bytes'], 4);
    expect(body['sd_free_bytes'], 1000 - 4 - 100);
  });

  test('no card: reports 0, keeps nothing, and asks for the list again once one is back', () async {
    server.put('a', 'AAAA');
    await frame.setCard('missing');
    await frame.sync();
    expect(server.syncBodies.last['sd_total_bytes'], 0);
    expect(server.syncBodies.last.containsKey('cache_bytes'), isFalse);
    expect(await cachedFiles(), isEmpty);
    expect(await frame.eraseCard(), isFalse, reason: 'nothing to erase');

    await frame.setCard('unreadable');
    expect((await frame.sdInfo())['state'], 'unreadable');
    expect(await frame.eraseCard(), isTrue);
    final r = await frame.sync();
    expect(server.syncBodies.last['manifest_version'], 0);
    expect(r.added, ['a']);
  });
}
