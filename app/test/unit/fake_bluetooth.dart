// A pretend frame in PAIRING for the Connect the frame tests: it behaves like
// docs/pairing.md says the firmware does (passkey, Wi-Fi scan, provision → status).
import 'dart:async';

import 'package:ink_frame/ble/frame_bluetooth.dart';
import 'package:ink_frame/ble/protocol.dart';

/// What the frame does with a pairing token: null when the claim works, else the
/// device-api error code (`invalid_pairing_token`, `model_mismatch`…).
typedef Claim = Future<String?> Function(Provision p, FrameInfo info);

class FakeHardware {
  FakeHardware({
    this.suffix = '1A2B',
    this.modelId = 'reterminal-e1002',
    this.frameId,
    this.networks = const [WifiNetwork('Home', rssi: -48), WifiNetwork('Neighbour', rssi: -80), WifiNetwork('Cafe', rssi: -60, secure: false)],
    this.passwords = const {'Home': 'correct horse', 'Cafe': ''},
    Claim? claim,
  }) : claim = claim ?? ((_, _) async => null);

  final String suffix;
  final String modelId;
  final String? frameId;
  final List<WifiNetwork> networks;
  final Map<String, String> passwords;
  final Claim claim;

  /// The next pairing attempt fails like this (then works).
  LinkFailure? failNextPair;

  /// The connection drops right after the frame reports this.
  LinkState? dropAfter;

  /// The frame stays silent after this (to test the quiet timeout).
  LinkState? silentAfter;

  final provisions = <Provision>[];
  var pairings = 0;
  var bondsRemoved = 0;
  var connected = false;

  String get hwId => 'e1002-24ec4a1b$suffix'.toLowerCase();
  FrameInfo get info => FrameInfo(hwId: hwId, modelId: modelId, fwVersion: '1.0.0', frameId: frameId);
  FoundFrame get found => FoundFrame('dev-$suffix', '${Pairing.namePrefix}$suffix', rssi: -50);
}

class FakeBluetooth implements FrameBluetooth {
  FakeBluetooth([List<FakeHardware>? frames]) : frames = frames ?? [FakeHardware()];

  final List<FakeHardware> frames;
  BluetoothState radio = BluetoothState.on;
  var allowed = true;
  var scans = 0;

  @override
  Future<BluetoothState> state() async => radio;

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Stream<FoundFrame> scan() {
    scans++;
    final out = StreamController<FoundFrame>();
    out.onListen = () {
      for (final f in frames) {
        out.add(f.found);
      }
    };
    return out.stream;
  }

  @override
  Future<PairingLink> connect(FoundFrame frame) async {
    final hw = frames.firstWhere((f) => f.found.id == frame.id);
    hw.connected = true;
    return _FakeLink(hw);
  }
}

class _FakeLink implements PairingLink {
  _FakeLink(this.hw);

  final FakeHardware hw;
  final _status = StreamController<LinkStatus>.broadcast();
  final _down = Completer<void>();

  @override
  Future<FrameInfo> pair() async {
    hw.pairings++;
    final fail = hw.failNextPair;
    if (fail != null) {
      hw.failNextPair = null;
      _drop();
      throw LinkException(fail, 'fake');
    }
    return hw.info;
  }

  @override
  Stream<WifiNetwork> wifiScan() => Stream.fromIterable(hw.networks);

  @override
  Stream<LinkStatus> get status => _status.stream;

  @override
  Future<void> provision(Provision p) async {
    if (_down.isCompleted) throw const LinkException(LinkFailure.lost, 'not connected');
    hw.provisions.add(p);
    unawaited(_run(p));
  }

  Future<void> _run(Provision p) async {
    Future<bool> say(LinkStatus s) async {
      await Future<void>.delayed(Duration.zero);
      if (_down.isCompleted || _status.isClosed) return false;
      _status.add(s);
      if (hw.dropAfter == s.state) {
        _drop();
        return false;
      }
      return hw.silentAfter != s.state;
    }

    if (!await say(const LinkStatus(LinkState.wifiConnecting))) return;
    final password = hw.passwords[p.ssid];
    if (password == null) {
      await say(const LinkStatus(LinkState.wifiFailed, reason: 'not_found'));
      return;
    }
    if (password != p.password) {
      await say(const LinkStatus(LinkState.wifiFailed, reason: 'auth'));
      return;
    }
    if (!await say(const LinkStatus(LinkState.claiming))) return;
    final error = await hw.claim(p, hw.info);
    if (error != null) {
      await say(LinkStatus(LinkState.error, code: error));
      return;
    }
    if (!await say(const LinkStatus(LinkState.claimed, frameId: 'f'))) return;
    if (!await say(const LinkStatus(LinkState.syncing))) return;
    await say(const LinkStatus(LinkState.ready));
  }

  void _drop() {
    hw.connected = false;
    if (!_down.isCompleted) _down.complete();
  }

  @override
  Future<void> get disconnected => _down.future;

  @override
  Future<void> close({bool forget = true}) async {
    if (forget) hw.bondsRemoved++;
    _drop();
    await _status.close();
  }
}
