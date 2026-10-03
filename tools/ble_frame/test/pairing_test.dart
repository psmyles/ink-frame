// The pretend frame's UUIDs match shared/pairing.json (docs/pairing.md).
import 'dart:convert';
import 'dart:io';

import 'package:ble_frame/pretend_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UUIDs and limits match shared/pairing.json', () {
    final j = jsonDecode(File('../../shared/pairing.json').readAsStringSync()) as Map<String, dynamic>;
    final c = j['characteristics'] as Map<String, dynamic>;
    expect(Pairing.namePrefix, j['name_prefix']);
    expect(Pairing.service, j['service']);
    expect([Pairing.info, Pairing.wifiScan, Pairing.provision, Pairing.status], [c['info'], c['wifi_scan'], c['provision'], c['status']]);
    expect(Pairing.maxMessageBytes, j['max_message_bytes']);
  });
}
