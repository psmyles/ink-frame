import 'protocol.dart';

enum BluetoothState { on, off, unauthorized, unsupported, unknown }

/// A frame in PAIRING, seen while scanning.
class FoundFrame {
  const FoundFrame(this.id, this.name, {this.rssi});

  /// The platform's device id.
  final String id;

  /// `InkFrame-XXXX`.
  final String name;
  final int? rssi;

  String get suffix => frameSuffix(name);
}

enum LinkFailure {
  /// Pairing failed: the code typed didn't match the frame's.
  wrongCode,

  /// The person closed the OS's pairing prompt.
  cancelled,

  /// The connection dropped, or the frame stopped answering.
  lost,

  /// Anything else (no such service, a write refused…).
  failed,
}

class LinkException implements Exception {
  const LinkException(this.failure, [this.message = '']);

  final LinkFailure failure;
  final String message;

  @override
  String toString() => 'LinkException(${failure.name}): $message';
}

/// Talks to frames over Bluetooth LE (docs/pairing.md). The app uses
/// `UniversalFrameBluetooth`; tests use a fake frame.
abstract interface class FrameBluetooth {
  Future<BluetoothState> state();

  /// Asks for Bluetooth permission where the OS wants it (Android 12+, iOS, macOS).
  /// False when refused.
  Future<bool> requestPermission();

  /// Frames advertising the pairing service, as they're seen; scanning stops when
  /// the subscription is cancelled. Errors with [LinkException] if it can't scan.
  Stream<FoundFrame> scan();

  /// Connects; [PairingLink.pair] comes next.
  Future<PairingLink> connect(FoundFrame frame);
}

/// One connection to a frame in PAIRING.
abstract interface class PairingLink {
  /// Reads `info`. On a new connection this makes the OS ask for the code shown on
  /// the frame. Throws [LinkException] ([LinkFailure.wrongCode], [LinkFailure.cancelled]…).
  Future<FrameInfo> pair();

  /// Asks the frame to scan for Wi-Fi; the networks as they arrive, then done.
  Stream<WifiNetwork> wifiScan();

  /// `status` notifications from now on.
  Stream<LinkStatus> get status;

  /// Sends the Wi-Fi details and pairing token; progress comes on [status].
  Future<void> provision(Provision p);

  /// Completes when the connection drops (or [close] is called).
  Future<void> get disconnected;

  /// Disconnects. [forget] also removes the OS's bond where it can, so the next
  /// pairing asks for the frame's new code (docs/pairing.md).
  Future<void> close({bool forget = true});
}
