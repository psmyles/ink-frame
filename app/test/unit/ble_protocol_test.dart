// The Bluetooth pairing messages (docs/pairing.md): the app's UUIDs match
// shared/pairing.json, and messages survive being split at any MTU.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/ble/protocol.dart';

void main() {
  test('UUIDs and limits match shared/pairing.json', () {
    final j = jsonDecode(File('../shared/pairing.json').readAsStringSync()) as Map<String, dynamic>;
    final c = j['characteristics'] as Map<String, dynamic>;
    expect(Pairing.namePrefix, j['name_prefix']);
    expect(Pairing.service, j['service']);
    expect([Pairing.info, Pairing.wifiScan, Pairing.provision, Pairing.status], [c['info'], c['wifi_scan'], c['provision'], c['status']]);
    expect(Pairing.maxMessageBytes, j['max_message_bytes']);
  });

  test('a message split at any size comes back whole, Unicode included', () {
    const p = Provision(ssid: 'Café ☕ 2.4', password: 'pässwörd', apiBaseUrl: 'https://abc.supabase.co/functions/v1', pairingToken: '01J9ZX3K7T8Q4M2N6P0R5S1V9W');
    final bytes = encodeMessage(p.toJson());
    expect(bytes.last, 0x0a);
    for (final size in [1, 7, 20, 244, 509]) {
      final reader = MessageReader();
      final out = [for (final c in chunks(bytes, size)) ...reader.add(c)];
      expect(out, hasLength(1), reason: 'size $size');
      expect(Provision.fromJson(out.single).toJson(), p.toJson());
    }
  });

  test('several messages in one chunk, and junk lines are skipped', () {
    final reader = MessageReader();
    final both = Uint8List.fromList([
      ...encodeMessage({'ssid': 'A', 'rssi': -40}),
      ...utf8.encode('not json\n'),
      ...encodeMessage({'done': true}),
    ]);
    expect(reader.add(both), [
      {'ssid': 'A', 'rssi': -40},
      {'done': true},
    ]);
  });

  test('a line longer than the limit is dropped, and reading carries on', () {
    final reader = MessageReader();
    final long = utf8.encode('{"x":"${'a' * 2000}"}\n');
    expect([for (final c in chunks(Uint8List.fromList(long), 100)) ...reader.add(c)], isEmpty);
    expect(reader.add(encodeMessage({'state': 'ready'})), [
      {'state': 'ready'},
    ]);
  });

  test('status: known states, and unknown ones are ignored', () {
    expect(LinkStatus.fromJson({'state': 'wifi_failed', 'reason': 'auth'})!.reason, 'auth');
    expect(LinkStatus.fromJson({'state': 'error', 'code': 'linked_elsewhere'})!.state, LinkState.error);
    expect(LinkStatus.fromJson({'state': 'rebooting'}), isNull);
    expect(const LinkStatus(LinkState.claimed, frameId: 'f').toJson(), {'state': 'claimed', 'frame_id': 'f'});
  });

  test('info, networks and the frame suffix', () {
    final info = FrameInfo.fromJson({'hw_id': 'e1002-24ec4a1b2c3d', 'model_id': 'reterminal-e1002', 'fw_version': '1.0.0', 'frame_id': null});
    expect((info.hwId, info.modelId, info.frameId), ('e1002-24ec4a1b2c3d', 'reterminal-e1002', null));
    expect([for (final r in [-40, -60, -70, -90]) WifiNetwork('x', rssi: r).bars], [3, 2, 1, 0]);
    expect(frameSuffix('InkFrame-1A2B'), '1A2B');
  });
}
