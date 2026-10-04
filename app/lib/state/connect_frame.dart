import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/frame_bluetooth.dart';
import '../ble/protocol.dart';
import '../ble/universal_frame_bluetooth.dart';
import '../data/api_error.dart';
import '../data/frame_link.dart';
import '../data/models.dart';
import 'frame_admin.dart';
import 'photos.dart';
import 'providers.dart';

/// Overridable for tests.
final frameBluetoothProvider = Provider<FrameBluetooth>((ref) => UniversalFrameBluetooth());

/// Connect the frame (app-flow §6.1): get ready → find → pair → Wi-Fi → finishing → done.
enum ConnectStep { ready, finding, choose, pairing, wifi, finishing, done }

/// What went wrong (app-flow §6.2), shown on the step it happened in.
enum ConnectProblem {
  bluetoothOff,
  permissionDenied,
  noBluetooth,
  noFrameFound,
  wrongCode,
  cancelled,
  modelMismatch,
  linkedElsewhere,
  wifiFailed,
  sdFailed,
  unreachable,
  offline,
  lost,
  failed,
}

class ConnectState {
  const ConnectState({
    this.step = ConnectStep.ready,
    this.found = const [],
    this.target,
    this.info,
    this.networks = const [],
    this.scanningWifi = false,
    this.ssid,
    this.eraseSd = false,
    this.progress,
    this.busy = false,
    this.problem,
    this.wifiReason,
    this.detail,
  });

  final ConnectStep step;

  /// Frames seen while finding, by their `XXXX`.
  final List<FoundFrame> found;

  /// The frame chosen (its `XXXX` matched the frame's screen), once connecting.
  final FoundFrame? target;

  /// The connected hardware's `info`, once paired.
  final FrameInfo? info;

  /// Networks the frame sees, strongest first.
  final List<WifiNetwork> networks;
  final bool scanningWifi;

  /// The network being joined (or that failed).
  final String? ssid;

  /// The memory card is erased first (finishing shows that step).
  final bool eraseSd;

  /// The last `status` while finishing.
  final LinkState? progress;

  /// Waiting on the server (switching the model).
  final bool busy;

  final ConnectProblem? problem;

  /// For [ConnectProblem.wifiFailed]: `auth`, `not_found` or `other`.
  final String? wifiReason;

  /// Technical detail, shown in developer mode.
  final String? detail;

  ConnectState copyWith({
    ConnectStep? step,
    List<FoundFrame>? found,
    FoundFrame? target,
    FrameInfo? info,
    List<WifiNetwork>? networks,
    bool? scanningWifi,
    String? ssid,
    bool? eraseSd,
    LinkState? progress,
    bool clearProgress = false,
    bool? busy,
  }) =>
      ConnectState(
        step: step ?? this.step,
        found: found ?? this.found,
        target: target ?? this.target,
        info: info ?? this.info,
        networks: networks ?? this.networks,
        scanningWifi: scanningWifi ?? this.scanningWifi,
        ssid: ssid ?? this.ssid,
        eraseSd: eraseSd ?? this.eraseSd,
        progress: clearProgress ? null : progress ?? this.progress,
        busy: busy ?? this.busy,
        problem: problem,
        wifiReason: wifiReason,
        detail: detail,
      );

  /// The same state with [problem] (or none).
  ConnectState withProblem(ConnectProblem? problem, {String? reason, String? detail}) => ConnectState(
        step: step,
        found: found,
        target: target,
        info: info,
        networks: networks,
        scanningWifi: scanningWifi,
        ssid: ssid,
        eraseSd: eraseSd,
        progress: progress,
        busy: false,
        problem: problem,
        wifiReason: reason,
        detail: detail,
      );
}

final connectFrameProvider =
    NotifierProvider.autoDispose.family<ConnectFrame, ConnectState, FrameAddress>(ConnectFrame.new);

class ConnectFrame extends Notifier<ConnectState> {
  ConnectFrame(this.address);

  final FrameAddress address;

  /// How long the frame may stay silent while joining Wi-Fi and claiming, and while
  /// getting its first photos.
  static const quietLimit = Duration(seconds: 45);

  /// Formatting a large card takes up to a minute or so.
  static const eraseLimit = Duration(minutes: 3);
  static const syncLimit = Duration(minutes: 3);

  /// Finding gives up after this. Once a frame is found, the ones seen within
  /// [settle] are offered: you match one's `XXXX` with the frame's screen, even when
  /// it's the only one (a neighbour's frame in PAIRING would otherwise be taken).
  static const findLimit = Duration(seconds: 30);
  static const scanLimit = Duration(seconds: 20);
  static const settle = Duration(seconds: 2);

  StreamSubscription<FoundFrame>? _scan;
  Timer? _findTimer, _settleTimer, _quiet, _scanTimer;
  StreamSubscription<WifiNetwork>? _wifi;
  StreamSubscription<LinkStatus>? _status;
  PairingLink? _link;
  FoundFrame? _target;
  String? _password;
  var _eraseSd = false;
  var _tokenRetried = false;

  @override
  ConnectState build() {
    ref.onDispose(_teardown);
    return const ConnectState();
  }

  FrameBluetooth get _bt => ref.read(frameBluetoothProvider);

  void _emit(ConnectState s) {
    if (ref.mounted) state = s;
  }

  Future<Frame?> _frame() async => (await ref.read(frameViewProvider(address).future)).summary?.frame;

  // ── Find ──

  /// Checks Bluetooth, then scans for frames in PAIRING.
  Future<void> start() async {
    await _stopScan();
    await _closeLink();
    _emit(const ConnectState(step: ConnectStep.finding));
    final bt = _bt;
    final allowed = await bt.requestPermission();
    final s = await bt.state();
    if (!ref.mounted) return;
    final problem = switch (s) {
      BluetoothState.off => ConnectProblem.bluetoothOff,
      BluetoothState.unauthorized => ConnectProblem.permissionDenied,
      BluetoothState.unsupported => ConnectProblem.noBluetooth,
      _ when !allowed => ConnectProblem.permissionDenied,
      _ => null,
    };
    if (problem != null) {
      _emit(const ConnectState().withProblem(problem));
      return;
    }

    final found = <String, FoundFrame>{};
    List<FoundFrame> sorted() => [...found.values]..sort((a, b) => a.suffix.compareTo(b.suffix));
    _findTimer = Timer(findLimit, () async {
      if (found.isNotEmpty) return;
      await _stopScan();
      _emit(const ConnectState().withProblem(ConnectProblem.noFrameFound));
    });
    _scan = bt.scan().listen(
      (f) {
        final first = found.isEmpty;
        // The name can come later than the first sighting (scan response).
        found[f.id] = f.name.isEmpty && found[f.id] != null ? found[f.id]! : f;
        _emit(state.copyWith(found: sorted()));
        if (first) _settleTimer = Timer(settle, () => _emit(state.copyWith(step: ConnectStep.choose)));
      },
      onError: (Object e) async {
        await _stopScan();
        _emit(const ConnectState().withProblem(ConnectProblem.failed, detail: '$e'));
      },
    );
  }

  /// Not awaited: universal_ble queues commands in order anyway, and a cancel's
  /// future can belong to another zone.
  Future<void> _stopScan() async {
    _findTimer?.cancel();
    _settleTimer?.cancel();
    unawaited(_scan?.cancel());
    _scan = null;
  }

  // ── Pair ──

  /// Connects to [frame], whose `XXXX` you matched with the frame's screen; the OS
  /// asks for the code on the frame's screen.
  Future<void> choose(FoundFrame frame) async {
    await _stopScan();
    await _closeLink();
    _target = frame;
    _emit(ConnectState(step: ConnectStep.pairing, found: state.found, target: frame));
    try {
      final link = await _bt.connect(frame);
      if (!ref.mounted) {
        await link.close();
        return;
      }
      _link = link;
      unawaited(link.disconnected.then((_) => _dropped(link)));
      final info = await link.pair();
      if (!ref.mounted) return;
      await _check(info);
    } on LinkException catch (e) {
      await _closeLink();
      final problem = switch (e.failure) {
        LinkFailure.wrongCode => ConnectProblem.wrongCode,
        LinkFailure.cancelled => ConnectProblem.cancelled,
        LinkFailure.lost => ConnectProblem.lost,
        LinkFailure.failed => ConnectProblem.failed,
      };
      _emit(state.copyWith(step: ConnectStep.pairing).withProblem(problem, detail: e.message));
    }
  }

  /// The hardware's model and link against this frame (docs/pairing.md, `info`).
  Future<void> _check(FrameInfo info) async {
    final frame = await _frame();
    if (frame == null) {
      _emit(state.copyWith(info: info).withProblem(ConnectProblem.failed, detail: 'frame not loaded'));
      return;
    }
    if (info.frameId != null && info.frameId != frame.id) {
      await _closeLink();
      _emit(state.copyWith(info: info).withProblem(ConnectProblem.linkedElsewhere));
    } else if (info.modelId != frame.modelId) {
      _emit(state.copyWith(info: info).withProblem(ConnectProblem.modelMismatch));
    } else {
      _emit(state.copyWith(step: ConnectStep.wifi, info: info).withProblem(null));
      scanWifi();
    }
  }

  /// Switches the frame to the connected hardware's model (clears the photos),
  /// then carries on to Wi-Fi.
  Future<void> switchModel() async {
    final info = state.info;
    if (info == null) return;
    _emit(state.copyWith(busy: true));
    try {
      await ref.read(frameApiProvider(address)).changeModel(info.modelId);
      ref.invalidate(frameViewProvider(address));
      ref.invalidate(photosProvider(address));
      await ref.read(frameViewProvider(address).future);
    } on ApiException catch (e) {
      _emit(state.withProblem(
        e.code == ApiException.offline ? ConnectProblem.offline : ConnectProblem.failed,
        detail: '$e',
      ));
      return;
    }
    if (_link == null) {
      _emit(state.withProblem(ConnectProblem.lost));
      return;
    }
    _emit(state.copyWith(step: ConnectStep.wifi).withProblem(null));
    scanWifi();
  }

  // ── Wi-Fi ──

  /// Asks the frame which networks it can see (again).
  void scanWifi() {
    final link = _link;
    if (link == null) return;
    unawaited(_wifi?.cancel());
    _scanTimer?.cancel();
    final seen = <String, WifiNetwork>{};
    _emit(state.copyWith(networks: const [], scanningWifi: true).withProblem(null));
    void stop() {
      _scanTimer?.cancel();
      unawaited(_wifi?.cancel());
      _wifi = null;
      _emit(state.copyWith(scanningWifi: false));
    }

    // A frame that never says "done" doesn't keep the list spinning. (Not
    // Stream.timeout, which holds back the end of the stream.)
    _scanTimer = Timer(scanLimit, stop);
    _wifi = link.wifiScan().listen(
      (n) {
        if (n.ssid.isEmpty) return;
        final old = seen[n.ssid];
        if (old == null || n.rssi > old.rssi) seen[n.ssid] = n;
        _emit(state.copyWith(networks: [...seen.values]..sort((a, b) => b.rssi.compareTo(a.rssi))));
      },
      onError: (Object _) => stop(),
      onDone: stop,
    );
  }

  // ── Finish ──

  /// Sends [ssid], [password], the API address and a fresh pairing token; with
  /// [eraseSd], the frame formats its memory card first.
  Future<void> join(String ssid, String password, {bool eraseSd = false}) async {
    final link = _link;
    if (link == null) {
      _emit(state.withProblem(ConnectProblem.lost));
      return;
    }
    unawaited(_wifi?.cancel());
    _scanTimer?.cancel();
    _password = password;
    _eraseSd = eraseSd;
    _tokenRetried = false;
    _emit(state
        .copyWith(step: ConnectStep.finishing, ssid: ssid, eraseSd: eraseSd, scanningWifi: false, clearProgress: true)
        .withProblem(null));
    _status ??= link.status.listen(_onStatus);
    await _send(link, ssid, password);
  }

  Future<void> _send(PairingLink link, String ssid, String password) async {
    try {
      final token = await ref.read(frameApiProvider(address)).createPairingToken();
      await link.provision(Provision(
        ssid: ssid,
        password: password,
        apiBaseUrl: '${address.url}/functions/v1',
        pairingToken: token.token,
        eraseSd: _eraseSd,
      ));
      _watch(_eraseSd ? eraseLimit : quietLimit);
    } on ApiException catch (e) {
      _emit(state.copyWith(step: ConnectStep.wifi).withProblem(
        e.code == ApiException.offline ? ConnectProblem.offline : ConnectProblem.failed,
        detail: '$e',
      ));
    } on LinkException catch (e) {
      _lost(e.message);
    }
  }

  void _onStatus(LinkStatus s) {
    if (state.step != ConnectStep.finishing) return;
    switch (s.state) {
      case LinkState.erasing:
        _watch(eraseLimit);
        _emit(state.copyWith(progress: s.state));
      case LinkState.wifiConnecting || LinkState.claiming || LinkState.claimed:
        // Erased already: a provision sent again (a new pairing token) doesn't erase again.
        _eraseSd = false;
        _watch(quietLimit);
        _emit(state.copyWith(progress: s.state));
      case LinkState.syncing:
        _watch(syncLimit);
        _emit(state.copyWith(progress: s.state));
      case LinkState.ready:
        unawaited(_finish());
      case LinkState.wifiFailed:
        _quiet?.cancel();
        _emit(state.copyWith(step: ConnectStep.wifi, clearProgress: true)
            .withProblem(ConnectProblem.wifiFailed, reason: s.reason ?? 'other'));
      case LinkState.error:
        _quiet?.cancel();
        final link = _link;
        if (s.code == 'invalid_pairing_token' && !_tokenRetried && link != null) {
          // Expired or used: a new one, without bothering anyone.
          _tokenRetried = true;
          unawaited(_send(link, state.ssid!, _password ?? ''));
          return;
        }
        final detail = '${s.code}${s.message == null ? '' : ': ${s.message}'}';
        switch (s.code) {
          case 'model_mismatch':
            _emit(state.copyWith(step: ConnectStep.pairing, clearProgress: true)
                .withProblem(ConnectProblem.modelMismatch, detail: detail));
          case 'linked_elsewhere':
            unawaited(_closeLink());
            _emit(state.copyWith(step: ConnectStep.pairing, clearProgress: true)
                .withProblem(ConnectProblem.linkedElsewhere, detail: detail));
          default:
            _emit(state.copyWith(step: ConnectStep.wifi, clearProgress: true).withProblem(
              switch (s.code) {
                'unreachable' => ConnectProblem.unreachable,
                'sd_failed' => ConnectProblem.sdFailed,
                _ => ConnectProblem.failed,
              },
              detail: detail,
            ));
        }
    }
  }

  bool get _linked => state.progress == LinkState.claimed || state.progress == LinkState.syncing;

  /// The frame has gone quiet: after claiming that's fine (it gets its photos on its
  /// own), before it the connection is lost.
  void _watch(Duration limit) {
    _quiet?.cancel();
    _quiet = Timer(limit, () => _linked ? _finish() : _lost('no answer for ${limit.inSeconds} s'));
  }

  void _dropped(PairingLink link) {
    if (!ref.mounted || _link != link) return;
    _link = null;
    if (state.step == ConnectStep.finishing && _linked) {
      unawaited(_finish());
    } else if (state.step != ConnectStep.done) {
      _lost('disconnected');
    }
  }

  void _lost(String detail) {
    _quiet?.cancel();
    unawaited(_closeLink());
    _emit(state.copyWith(step: ConnectStep.pairing, clearProgress: true).withProblem(ConnectProblem.lost, detail: detail));
  }

  Future<void> _finish() async {
    _quiet?.cancel();
    _emit(state.copyWith(step: ConnectStep.done).withProblem(null));
    ref.invalidate(frameViewProvider(address));
    await _closeLink();
  }

  /// Try again after a problem: the code again for the same frame, otherwise find
  /// it again.
  Future<void> retry() async {
    final target = _target;
    final again = state.problem == ConnectProblem.wrongCode || state.problem == ConnectProblem.cancelled;
    if (again && target != null) {
      await choose(target);
    } else {
      await start();
    }
  }

  Future<void> _closeLink() async {
    final link = _link;
    _link = null;
    unawaited(_status?.cancel());
    _status = null;
    unawaited(_wifi?.cancel());
    _wifi = null;
    _scanTimer?.cancel();
    await link?.close();
  }

  void _teardown() {
    _quiet?.cancel();
    _scanTimer?.cancel();
    unawaited(_stopScan());
    unawaited(_closeLink());
  }
}
