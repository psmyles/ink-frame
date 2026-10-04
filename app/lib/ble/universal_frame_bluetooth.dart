import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

import 'frame_bluetooth.dart';
import 'protocol.dart';

/// [FrameBluetooth] on universal_ble (Android, iOS, macOS, Windows, Linux).
class UniversalFrameBluetooth implements FrameBluetooth {
  @override
  Future<BluetoothState> state() async {
    try {
      var s = await UniversalBle.getBluetoothAvailabilityState();
      // Apple reports "unknown" until the radio has started.
      if (s == AvailabilityState.unknown || s == AvailabilityState.resetting) {
        s = await UniversalBle.availabilityStream
            .firstWhere((s) => s != AvailabilityState.unknown && s != AvailabilityState.resetting)
            .timeout(const Duration(seconds: 3), onTimeout: () => s);
      }
      return switch (s) {
        AvailabilityState.poweredOn => BluetoothState.on,
        AvailabilityState.poweredOff => BluetoothState.off,
        AvailabilityState.unauthorized => BluetoothState.unauthorized,
        AvailabilityState.unsupported => BluetoothState.unsupported,
        _ => BluetoothState.unknown,
      };
    } catch (_) {
      return BluetoothState.unsupported;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await UniversalBle.requestPermissions();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<FoundFrame> scan() {
    StreamSubscription<BleDevice>? sub;
    late final StreamController<FoundFrame> out;
    out = StreamController(
      onListen: () async {
        sub = UniversalBle.scanStream.listen((d) {
          final name = d.name ?? '';
          final ours = d.services.any((s) => BleUuidParser.compareStrings(s, Pairing.service)) ||
              name.startsWith(Pairing.namePrefix);
          if (ours) out.add(FoundFrame(d.deviceId, name, rssi: d.rssi));
        });
        try {
          await UniversalBle.startScan(
            scanFilter: ScanFilter(withServices: [Pairing.service], withNamePrefix: [Pairing.namePrefix]),
            // The ESP32 advertises the classic (legacy) way.
            platformConfig: PlatformConfig(
              android: AndroidOptions(legacy: true, scanMode: AndroidScanMode.lowLatency, requestLocationPermission: false),
            ),
          );
        } catch (e) {
          out.addError(LinkException(LinkFailure.failed, '$e'));
        }
      },
      onCancel: () async {
        await sub?.cancel();
        try {
          await UniversalBle.stopScan();
        } catch (_) {
          // Already stopped.
        }
      },
    );
    return out.stream;
  }

  @override
  Future<PairingLink> connect(FoundFrame frame) async {
    try {
      // A bond left from an earlier session has keys the frame no longer has.
      if (BleCapabilities.hasSystemPairingApi && (await UniversalBle.isPaired(frame.id) ?? false)) {
        await UniversalBle.unpair(frame.id);
      }
    } catch (_) {
      // Not paired.
    }
    final link = _Link(frame.id);
    await link._open();
    return link;
  }
}

class _Link implements PairingLink {
  _Link(this.id);

  final String id;
  final _disconnected = Completer<void>();
  final _status = StreamController<LinkStatus>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  var _chunk = 20;
  var _subscribedWifi = false;

  Future<void> _open() async {
    _subs.add(UniversalBle.connectionStream(id).listen((up) {
      if (!up && !_disconnected.isCompleted) _disconnected.complete();
    }));
    try {
      await UniversalBle.connect(id, timeout: const Duration(seconds: 20));
      await UniversalBle.discoverServices(id);
    } catch (e) {
      await close(forget: false);
      throw _failure(e, LinkFailure.lost);
    }
    try {
      final mtu = await UniversalBle.requestMtu(id, Pairing.preferredMtu);
      _chunk = (mtu - 3).clamp(20, 509);
    } catch (_) {
      // Keep 20 bytes.
    }
  }

  /// Errors that mean "pair first".
  static const _needsPairing = {
    UniversalBleErrorCode.insufficientAuthentication,
    UniversalBleErrorCode.insufficientEncryption,
    UniversalBleErrorCode.insufficientKeySize,
    UniversalBleErrorCode.protectionLevelNotMet,
    UniversalBleErrorCode.authenticationFailure,
    UniversalBleErrorCode.notPaired,
  };

  @override
  Future<FrameInfo> pair() async {
    try {
      // `info` needs an encrypted link: reading it makes Android, iOS and macOS pair
      // (asking for the frame's code) and then retry the read. An explicit bond
      // first would be refused by a frame that only pairs on demand.
      Future<Uint8List> read() => UniversalBle.read(id, Pairing.service, Pairing.info, timeout: const Duration(minutes: 3));
      Uint8List bytes;
      try {
        bytes = await read();
      } on UniversalBleException catch (e) {
        // Windows and Linux don't pair by themselves: bond, then read again.
        if (!_needsPairing.contains(e.code) || !BleCapabilities.hasSystemPairingApi) rethrow;
        try {
          await UniversalBle.pair(id, timeout: const Duration(minutes: 3));
        } on PairingException catch (e) {
          // A refused bond doesn't say why; most often the code didn't match.
          throw LinkException(LinkFailure.wrongCode, '${e.code.name}: ${e.message}');
        }
        bytes = await read();
      }
      final info = FrameInfo.fromJson(jsonDecode(utf8.decode(bytes).trim()) as Map<String, dynamic>);

      final reader = MessageReader();
      _subs.add(UniversalBle.characteristicValueStream(id, Pairing.status).listen((v) {
        for (final m in reader.add(v)) {
          final s = LinkStatus.fromJson(m);
          if (s != null) _status.add(s);
        }
      }));
      await UniversalBle.subscribeNotifications(id, Pairing.service, Pairing.status);
      return info;
    } on LinkException {
      rethrow;
    } catch (e) {
      throw _failure(e, LinkFailure.failed);
    }
  }

  @override
  Stream<WifiNetwork> wifiScan() {
    StreamSubscription<Uint8List>? sub;
    late final StreamController<WifiNetwork> out;
    out = StreamController(
      onListen: () async {
        final reader = MessageReader();
        sub = UniversalBle.characteristicValueStream(id, Pairing.wifiScan).listen((v) {
          for (final m in reader.add(v)) {
            if (m['done'] == true) {
              out.close();
            } else if (m['ssid'] is String) {
              out.add(WifiNetwork.fromJson(m));
            }
          }
        });
        try {
          if (!_subscribedWifi) {
            await UniversalBle.subscribeNotifications(id, Pairing.service, Pairing.wifiScan);
            _subscribedWifi = true;
          }
          await _write(Pairing.wifiScan, {'scan': true});
        } catch (e) {
          out.addError(_failure(e, LinkFailure.failed));
          await out.close();
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Stream<LinkStatus> get status => _status.stream;

  @override
  Future<void> provision(Provision p) async {
    try {
      await _write(Pairing.provision, p.toJson());
    } catch (e) {
      throw _failure(e, LinkFailure.lost);
    }
  }

  Future<void> _write(String characteristic, Map<String, Object?> message) async {
    for (final c in chunks(encodeMessage(message), _chunk)) {
      await UniversalBle.write(id, Pairing.service, characteristic, c);
    }
  }

  @override
  Future<void> get disconnected => _disconnected.future;

  @override
  Future<void> close({bool forget = true}) async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    try {
      await UniversalBle.disconnect(id, timeout: const Duration(seconds: 5));
    } catch (_) {
      // Already gone.
    }
    if (forget && BleCapabilities.hasSystemPairingApi) {
      try {
        await UniversalBle.unpair(id);
      } catch (_) {
        // Not paired.
      }
    }
    if (!_disconnected.isCompleted) _disconnected.complete();
    await _status.close();
  }

  /// A universal_ble error as a [LinkFailure].
  LinkException _failure(Object e, LinkFailure otherwise) {
    if (e is LinkException) return e;
    if (e is UniversalBleException) {
      final failure = switch (e.code) {
        UniversalBleErrorCode.pairingFailed ||
        UniversalBleErrorCode.authenticationFailure ||
        UniversalBleErrorCode.insufficientAuthentication ||
        UniversalBleErrorCode.insufficientEncryption ||
        UniversalBleErrorCode.insufficientKeySize ||
        UniversalBleErrorCode.protectionLevelNotMet ||
        UniversalBleErrorCode.notPaired =>
          LinkFailure.wrongCode,
        UniversalBleErrorCode.pairingCancelled ||
        UniversalBleErrorCode.pairingTimeout ||
        UniversalBleErrorCode.operationCancelled =>
          LinkFailure.cancelled,
        UniversalBleErrorCode.deviceDisconnected ||
        UniversalBleErrorCode.connectionTerminated ||
        UniversalBleErrorCode.connectionTimeout ||
        UniversalBleErrorCode.connectionFailed ||
        UniversalBleErrorCode.deviceNotFound =>
          LinkFailure.lost,
        _ => otherwise,
      };
      return LinkException(failure, '${e.code.name}: ${e.message}');
    }
    if (e is TimeoutException) return LinkException(LinkFailure.lost, 'timed out');
    return LinkException(otherwise, '$e');
  }
}
