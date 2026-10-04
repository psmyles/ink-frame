// Connecting hardware (3f) through the real backend: the app's pairing token, a
// claim and syncs the way the firmware makes them (docs/pairing.md), the frame
// showing it, switching the model with photos on it, and disconnecting. Run with
// `deno run --allow-all tools/dev/app-live-test.ts`.
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ink_frame/data/frame_api.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/photos.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/imaging/pipeline.dart';

void main() {
  final raw = Platform.environment['INKFRAME_LIVE'];
  if (raw == null) {
    test('live tests', () {}, skip: 'Run through tools/dev/app-live-test.ts');
    return;
  }
  final fx = jsonDecode(raw) as Map<String, dynamic>;
  final address = FrameAddress(fx['url'] as String, fx['key'] as String);
  final run = DateTime.now().microsecondsSinceEpoch.toRadixString(16);

  late FrameConnection conn;
  late FrameApi owner;

  setUpAll(() async {
    final repo = FramesRepository(MemoryStore());
    await repo.signIn(address, PasswordCredential(fx['owner_email'] as String, fx['owner_password'] as String));
    conn = await repo.ready(address);
    owner = FrameApi(conn);
  });

  /// device-api, as the hardware calls it.
  Future<(int, Map<String, dynamic>?)> device(String path, Map<String, Object?> body, {String? secret}) async {
    final res = await http.post(
      Uri.parse('${address.url}/functions/v1/device-api/$path'),
      headers: {'Content-Type': 'application/json', if (secret != null) 'Authorization': 'Bearer $secret'},
      body: jsonEncode(body),
    );
    return (res.statusCode, res.body.isEmpty ? null : jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<(int, Map<String, dynamic>?)> claim(String token, String hwId, {String model = 'reterminal-e1002'}) =>
      device('claim', {'pairing_token': token, 'hw_id': hwId, 'model_id': model, 'fw_version': '0.0.0-live'});

  Future<int> sync(String secret) async =>
      (await device('sync', {'manifest_version': 0, 'fw_version': '0.0.0-live', 'battery_pct': 77, 'local_ids': <String>[]}, secret: secret)).$1;

  test('a pairing token connects hardware once; the frame shows it; disconnect wipes it', () async {
    final hw = 'live-$run';
    final token = await owner.createPairingToken();
    expect(token.token, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
    expect(token.expiresAt.difference(DateTime.now()).inMinutes, inInclusiveRange(8, 10));

    final (status, body) = await claim(token.token, hw);
    expect(status, 200, reason: '$body');
    final secret = body!['device_secret'] as String;
    var frame = (await conn.loadSummary()).frame;
    expect((frame.connected, frame.hwId, frame.fwVersion), (true, hw, '0.0.0-live'));
    expect(body['frame_id'], frame.id);

    // One use.
    expect((await claim(token.token, hw)).$1, 401);

    expect(await sync(secret), 200);
    frame = (await conn.loadSummary()).frame;
    expect(frame.batteryPct, 77);
    expect(frame.lastSeenAt, isNotNull);

    await owner.disconnect();
    expect(await sync(secret), 410);
    frame = (await conn.loadSummary()).frame;
    expect((frame.connected, frame.hwId), (false, null));
  });

  test('a different model is refused; switching the model clears the photos and the hardware', () async {
    // The test-only second model that tools/dev/app-live-test.ts adds (backend/supabase/tests/_lib.ts).
    const otherModel = 'test-other-7-3';
    final token = await owner.createPairingToken();
    final (status, body) = await claim(token.token, 'live-other-$run', model: otherModel);
    expect(status, 409);
    expect((body!['error'] as Map)['code'], 'model_mismatch');

    // Hardware and a photo on the frame first.
    final (_, claimed) = await claim((await owner.createPairingToken()).token, 'live-$run');
    final secret = claimed!['device_secret'] as String;
    final photos = PhotosRepository(conn);
    final model = await photos.model('reterminal-e1002');
    final r = math.Random(7);
    final p = preparePhoto(
      PhotoJob(
        rgba: Uint8List.fromList(List.generate(800 * 480 * 4, (i) => i % 4 == 3 ? 255 : r.nextInt(256))),
        width: 800,
        height: 480,
        outWidth: 800,
        outHeight: 480,
        palette: Palette.fromJson(model.palette),
      ),
      zopfliIterations: 1,
    );
    await photos.upload(p.png, p.sha256, p.width, p.height);
    expect(await photos.list(), isNotEmpty);

    final switched = await owner.changeModel(otherModel);
    expect((switched.modelId, switched.connected), (otherModel, false));
    expect(await PhotosRepository(conn).list(), isEmpty);
    expect(await sync(secret), 410);

    // Now the other model's hardware claims, and the frame goes back to the E1002 for the other tests.
    expect((await claim((await owner.createPairingToken()).token, 'live-other-$run', model: otherModel)).$1, 200);
    expect((await owner.changeModel('reterminal-e1002')).modelId, 'reterminal-e1002');
  });
}
