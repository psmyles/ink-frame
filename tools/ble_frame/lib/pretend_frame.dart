import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:frame_sim/frame_sim.dart' as sim;
import 'package:universal_ble/universal_ble.dart';

/// shared/pairing.json (test/pairing_test.dart checks these match).
abstract final class Pairing {
  static const namePrefix = 'InkFrame-';
  static const service = '42a40001-0087-4bd2-ab9b-8b4febd5191e';
  static const info = '42a40002-0087-4bd2-ab9b-8b4febd5191e';
  static const wifiScan = '42a40003-0087-4bd2-ab9b-8b4febd5191e';
  static const provision = '42a40004-0087-4bd2-ab9b-8b4febd5191e';
  static const status = '42a40005-0087-4bd2-ab9b-8b4febd5191e';
  static const maxMessageBytes = 1024;
}

/// Pretend Wi-Fi: every network joins with any password except `wrong`; "Far away"
/// is never found.
const fakeNetworks = [
  {'ssid': 'Home', 'rssi': -45, 'secure': true},
  {'ssid': 'Garden', 'rssi': -66, 'secure': true},
  {'ssid': 'Cafe', 'rssi': -72, 'secure': false},
  {'ssid': 'Far away', 'rssi': -90, 'secure': true},
];

/// The firmware's side of docs/pairing.md over real Bluetooth, with frame_sim doing
/// the claiming and syncing over HTTPS.
class PretendFrame extends ChangeNotifier {
  PretendFrame(this.frame);

  final sim.Frame frame;

  /// Newest first.
  final log = <String>[];

  /// Shown like the firmware's PAIRING screen. Only enforced by the OS when pairing
  /// is required, and then the OS picks its own code (a Mac can't use a fixed one).
  var passkey = '';
  var advertising = false;
  /// Off by default: a Mac refuses LE pairing as a peripheral, and can't use the
  /// frame's fixed code anyway (seen with an Android phone, 2026-10-04).
  var requireEncryption = false;
  String? central;
  File? showing;
  var busy = false;

  var _notifyLength = 20;
  final _buffers = <String, BytesBuilder>{};
  final _subs = <StreamSubscription<Object?>>[];

  String get hwId => frame.config['hw_id'] as String;
  String get modelId => frame.config['model_id'] as String;
  String get suffix {
    final hex = hwId.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase().padLeft(4, '0');
    return hex.substring(hex.length - 4);
  }

  String get name => '${Pairing.namePrefix}$suffix';

  Future<void> init() async {
    await frame.load();
    _subs
      ..add(UniversalBlePeripheral.connectionStateStream.listen((e) {
        central = e.connected ? e.deviceId : null;
        if (!e.connected) _buffers.clear();
        _say(e.connected ? 'Phone connected (${e.deviceId})' : 'Phone disconnected');
      }))
      ..add(UniversalBlePeripheral.mtuChangedStream.listen((e) {
        _notifyLength = max(20, e.mtu - 3);
        _say('MTU ${e.mtu}');
      }))
      ..add(UniversalBlePeripheral.characteristicSubscriptionStream.listen((e) {
        _say('${e.isSubscribed ? 'Subscribed to' : 'Unsubscribed from'} ${_short(e.characteristicId)}');
      }));
    UniversalBlePeripheral.setReadRequestHandlers(_onRead);
    UniversalBlePeripheral.setWriteRequestHandlers(_onWrite);
    if (frame.isPaired) {
      await _showNext();
      _say('Linked to ${frame.config['api_base_url']}. Hold 3 s to pair again.');
    } else {
      await startPairing();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    UniversalBlePeripheral.setReadRequestHandlers(null);
    UniversalBlePeripheral.setWriteRequestHandlers(null);
    super.dispose();
  }

  // ── Buttons ──

  /// Green button held 3 s: PAIRING.
  Future<void> startPairing() async {
    passkey = List.generate(6, (_) => Random.secure().nextInt(10)).join();
    try {
      final caps = await UniversalBlePeripheral.getCapabilities();
      if (!caps.supportsPeripheralMode) {
        _say("This device can't act as a Bluetooth frame.");
        return;
      }
      final ready = await UniversalBlePeripheral.getAvailabilityState();
      if (ready != PeripheralReadinessState.ready) {
        _say('Bluetooth not ready: ${ready.name}');
        return;
      }
      await UniversalBlePeripheral.stopAdvertising();
      await UniversalBlePeripheral.clearServices();
      final read = [requireEncryption ? PeripheralAttributePermission.readEncryptionRequired : PeripheralAttributePermission.readable];
      final write = [requireEncryption ? PeripheralAttributePermission.writeEncryptionRequired : PeripheralAttributePermission.writeable];
      await UniversalBlePeripheral.addService(BlePeripheralService(
        uuid: Pairing.service,
        primary: true,
        characteristics: [
          BlePeripheralCharacteristic(uuid: Pairing.info, properties: [CharacteristicProperty.read], permissions: read),
          BlePeripheralCharacteristic(
            uuid: Pairing.wifiScan,
            properties: [CharacteristicProperty.write, CharacteristicProperty.notify],
            permissions: [...read, ...write],
          ),
          BlePeripheralCharacteristic(uuid: Pairing.provision, properties: [CharacteristicProperty.write], permissions: write),
          BlePeripheralCharacteristic(uuid: Pairing.status, properties: [CharacteristicProperty.notify], permissions: read),
        ],
      ));
      await UniversalBlePeripheral.startAdvertising(services: [Pairing.service], localName: name);
      advertising = true;
      showing = null;
      _say('Advertising as $name (${requireEncryption ? 'pairing required' : 'no pairing'})');
    } catch (e) {
      _say('Bluetooth error: $e');
    }
  }

  /// Green button: check for new photos now, then show the newest.
  Future<void> checkNow() async {
    if (!frame.isPaired) return;
    await _run(() async {
      final r = await frame.sync();
      _say('Checked: ${r.total} photos (+${r.added.length} -${r.removed.length})');
      await _showNext(newest: r.added.isNotEmpty ? r.added.last : null);
    });
  }

  /// White button: the next photo.
  Future<void> next() => _showNext();

  /// Green button held 10 s: forget everything.
  Future<void> factoryReset() async {
    await UniversalBlePeripheral.stopAdvertising();
    advertising = false;
    if (await frame.dir.exists()) await frame.dir.delete(recursive: true);
    frame.config = {};
    await frame.load();
    showing = null;
    _say('Reset: new hw_id $hwId');
    await startPairing();
  }

  int get battery => frame.config['battery_pct'] as int? ?? 100;

  /// What it reports at its next check (to try the low-battery notification).
  Future<void> setBattery(int pct) async {
    frame.config['battery_pct'] = pct;
    await frame.save();
    notifyListeners();
  }

  Future<void> setModel(String id) async {
    frame.config['model_id'] = id;
    await frame.save();
    notifyListeners();
  }

  // ── GATT ──

  PeripheralReadRequestResult? _onRead(String device, String characteristic, int offset, Uint8List? value) {
    if (!_same(characteristic, Pairing.info)) return null;
    final info = utf8.encode(jsonEncode({
      'hw_id': hwId,
      'model_id': modelId,
      'fw_version': sim.fwVersion,
      'frame_id': frame.isPaired ? frame.config['frame_id'] : null,
    }));
    if (offset == 0) _say('Phone read info (paired)');
    return PeripheralReadRequestResult(value: Uint8List.sublistView(info, min(offset, info.length)));
  }

  PeripheralWriteRequestResult? _onWrite(String device, String characteristic, int offset, Uint8List? value) {
    final key = _same(characteristic, Pairing.provision)
        ? Pairing.provision
        : _same(characteristic, Pairing.wifiScan)
            ? Pairing.wifiScan
            : null;
    if (key == null || value == null) return null;
    final buffer = _buffers.putIfAbsent(key, BytesBuilder.new)..add(value);
    final bytes = buffer.toBytes();
    final end = bytes.indexOf(0x0a);
    if (end < 0) {
      if (bytes.length > Pairing.maxMessageBytes) {
        buffer.clear();
        _notify(Pairing.status, {'state': 'error', 'code': 'bad_request'});
      }
      return PeripheralWriteRequestResult();
    }
    buffer
      ..clear()
      ..add(bytes.sublist(end + 1));
    try {
      final message = jsonDecode(utf8.decode(bytes.sublist(0, end))) as Map<String, dynamic>;
      if (key == Pairing.wifiScan) {
        unawaited(_scanWifi());
      } else {
        unawaited(_provision(message));
      }
    } catch (_) {
      _notify(Pairing.status, {'state': 'error', 'code': 'bad_request'});
    }
    return PeripheralWriteRequestResult();
  }

  Future<void> _scanWifi() async {
    _say('Scanning Wi-Fi (pretend)');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    for (final n in fakeNetworks) {
      await _notify(Pairing.wifiScan, n);
    }
    await _notify(Pairing.wifiScan, {'done': true});
  }

  Future<void> _provision(Map<String, dynamic> m) async {
    final ssid = m['ssid'] as String? ?? '';
    final base = (m['api_base_url'] as String? ?? '').replaceAll(RegExp(r'/+$'), '');
    _say('Provision: Wi-Fi "$ssid", $base');
    await _status({'state': 'wifi_connecting'});
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (ssid == 'Far away' || ssid.isEmpty) return _status({'state': 'wifi_failed', 'reason': 'not_found'});
    if (m['password'] == 'wrong') return _status({'state': 'wifi_failed', 'reason': 'auth'});
    if (frame.isPaired && frame.config['api_base_url'] != base) {
      return _status({'state': 'error', 'code': 'linked_elsewhere'});
    }

    await _status({'state': 'claiming'});
    final String frameId;
    try {
      frameId = await frame.claim(apiBaseUrl: base, pairingToken: m['pairing_token'] as String);
    } on sim.ApiException catch (e) {
      final code = switch (e.code) {
        'invalid_pairing_token' || 'model_mismatch' || 'unknown_model' => e.code,
        _ => 'server',
      };
      await _status({'state': 'error', 'code': code, 'message': e.message});
      return;
    } catch (e) {
      // No answer from the API (offline, DNS, TLS).
      await _status({'state': 'error', 'code': 'unreachable', 'message': '$e'});
      return;
    }

    // Linked: from here on the frame finishes whatever happens to the phone, like the
    // firmware (a status the phone doesn't get is only logged).
    _say('Linked to frame $frameId');
    await _status({'state': 'claimed', 'frame_id': frameId});
    await _status({'state': 'syncing'});
    try {
      final r = await frame.sync(force: true);
      _say('First check: ${r.total} photos');
    } catch (e) {
      _say('First check failed ($e); the frame retries later');
    }
    await _status({'state': 'ready'});
    await _stopAdvertising();
    await _showNext();
  }

  Future<void> _stopAdvertising() async {
    advertising = false;
    try {
      await UniversalBlePeripheral.stopAdvertising();
    } catch (e) {
      _say('Stop advertising: $e');
    }
    notifyListeners();
  }

  Future<void> _status(Map<String, Object?> s) async {
    _say('→ ${s['state']}${s['code'] == null ? '' : ' ${s['code']}'}${s['reason'] == null ? '' : ' (${s['reason']})'}');
    await _notify(Pairing.status, s);
  }

  /// One message, in chunks the phone can take. Never throws: the Mac refuses a
  /// notification when the phone has gone or its send queue is full; the first is
  /// logged, the second retried.
  Future<void> _notify(String characteristic, Map<String, Object?> message) async {
    final bytes = utf8.encode('${jsonEncode(message)}\n');
    for (var i = 0; i < bytes.length; i += _notifyLength) {
      final chunk = Uint8List.sublistView(bytes, i, min(i + _notifyLength, bytes.length));
      for (var attempt = 1;; attempt++) {
        try {
          await UniversalBlePeripheral.updateCharacteristicValue(
            characteristicId: characteristic,
            value: chunk,
            deviceId: central,
          );
          break;
        } catch (e) {
          if (attempt >= 5 || central == null || !'$e'.contains('queue full')) {
            _say('Couldn\'t tell the phone (${message['state'] ?? _short(characteristic)}): $e');
            return;
          }
          await Future<void>.delayed(Duration(milliseconds: 100 * attempt));
        }
      }
    }
  }

  // ── Showing photos ──

  Future<void> _showNext({String? newest}) async {
    final images = await frame.readManifest();
    if (images.isEmpty) {
      showing = null;
    } else if (newest != null) {
      showing = frame.imageFile(newest);
    } else {
      final pick = await frame.pickNext();
      showing = pick == null ? null : frame.imageFile(pick.id);
    }
    _say(showing == null ? 'No photos yet' : 'Showing ${showing!.uri.pathSegments.last} (${images.length} cached)');
  }

  Future<void> _run(Future<void> Function() body) async {
    busy = true;
    notifyListeners();
    try {
      await body();
    } on sim.ApiException catch (e) {
      _say(e.status == 410 ? 'This frame was removed. Hold 3 s to set it up again.' : 'Error: $e');
      if (e.status == 410) showing = null;
    } catch (e) {
      _say('Error: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _say(String line) {
    final t = DateTime.now();
    log.insert(0, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}  $line');
    if (log.length > 200) log.removeLast();
    debugPrint(line);
    // Also on disk, so the log can be read from outside the app.
    try {
      File('${frame.dir.path}/log.txt').writeAsStringSync('${t.toIso8601String()}  $line\n', mode: FileMode.append);
    } catch (_) {
      // Not set up yet.
    }
    notifyListeners();
  }

  static bool _same(String a, String b) => BleUuidParser.compareStrings(a, b);
  static String _short(String uuid) => switch (uuid.toLowerCase()) {
        Pairing.info => 'info',
        Pairing.wifiScan => 'wifi_scan',
        Pairing.provision => 'provision',
        Pairing.status => 'status',
        _ => uuid,
      };
}
