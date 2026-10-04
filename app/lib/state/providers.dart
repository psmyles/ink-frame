import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/sign_in_service.dart';
import '../battery/battery_watch.dart';
import '../battery/notifications.dart';
import '../config/app_config.dart';
import '../data/api_error.dart';
import '../data/frame_api.dart';
import '../data/frame_connection.dart';
import '../data/frame_directory.dart';
import '../data/frame_link.dart';
import '../data/frames_repository.dart';
import '../data/models.dart';
import '../data/secure_store.dart';

final storeProvider = Provider<KeyValueStore>((ref) => SecureStore());

final framesRepositoryProvider = Provider<FramesRepository>((ref) => FramesRepository(ref.watch(storeProvider)));

final signInServiceProvider = Provider<SignInService>((ref) => SignInService());

final frameDirectoryProvider = Provider<FrameDirectory>((ref) => FrameDirectory(ref.watch(storeProvider)));

/// The low-battery notification's watch tokens (phones only).
final batteryWatchProvider = Provider<BatteryWatch>(
  (ref) => BatteryWatch(SecureStore.background(), supported: Platform.isAndroid || Platform.isIOS),
);

final notificationsProvider = Provider<Notifications>((ref) => Notifications());

/// A frame's connection. Invalidated when the frame is removed or signed in to
/// again, so everything read through it (the frame, photos, people, …) is read
/// afresh instead of from the session before.
final connectionProvider = Provider.family<FrameConnection, FrameAddress>(
  (ref, a) => ref.watch(framesRepositoryProvider).connection(a),
);

/// The frames on this device, in the order they were added.
final framesProvider = AsyncNotifierProvider<FramesNotifier, List<FrameAddress>>(FramesNotifier.new);

class FramesNotifier extends AsyncNotifier<List<FrameAddress>> {
  FramesRepository get _repo => ref.read(framesRepositoryProvider);

  @override
  Future<List<FrameAddress>> build() {
    // Directory changes that couldn't be sent last time (offline).
    unawaited(ref.read(frameDirectoryProvider).flush());
    return _repo.load();
  }

  Future<void> reload() async => state = AsyncData(await _repo.load());

  Future<void> remove(FrameAddress a) async {
    unawaited(ref.read(batteryWatchProvider).forget(a));
    await _repo.remove(a);
    ref.invalidate(connectionProvider(a));
    await reload();
  }

  /// "Remove from this device" for a frame you were removed from or that no longer
  /// exists: also off your account's list, so other devices stop offering it.
  Future<void> drop(FrameAddress a) async {
    unawaited(ref.read(frameDirectoryProvider).remove([a]));
    await remove(a);
  }

  Future<void> signOutAll() async {
    unawaited(ref.read(batteryWatchProvider).forgetAll());
    await _repo.signOutAll();
    ref.invalidate(connectionProvider);
    await reload();
  }

  /// After signing in to or joining [frames]: drop what was read for them before
  /// (e.g. "signed out" from the last sign-out) and reload the list.
  Future<void> signedIn(List<FrameAddress> frames) async {
    for (final f in frames) {
      ref.invalidate(connectionProvider(f));
    }
    await reload();
  }
}

/// What a card or frame screen shows: the live summary, or an error with the last
/// known name. Never fails, so the UI only handles loading and data.
class FrameView {
  const FrameView({this.summary, this.error, this.cached});

  final FrameSummary? summary;
  final ApiException? error;
  final CachedFrame? cached;

  String? get name => summary?.frame.name ?? cached?.name;
}

final frameViewProvider = FutureProvider.family<FrameView, FrameAddress>((ref, address) async {
  ref.watch(connectionProvider(address));
  final repo = ref.read(framesRepositoryProvider);
  ApiException error;
  try {
    final conn = await repo.ready(address);
    if (!conn.isSignedIn) throw const ApiException(ApiException.signedOut, 'Not signed in.');
    final summary = await conn.loadSummary();
    await repo.remember(address, summary);
    unawaited(ref.read(batteryWatchProvider).sync(address, summary, FrameApi(conn)).catchError((_) {}));
    return FrameView(summary: summary);
  } on ApiException catch (e) {
    error = e;
  }
  // A deleted project looks offline (its address is gone) or signed out (the
  // refresh was refused), so ask.
  const known = {ApiException.asleep, ApiException.notMember, ApiException.gone};
  if (!known.contains(error.code) && await repo.connection(address).isGone()) {
    error = const ApiException(ApiException.gone, 'The frame no longer exists.');
  }
  return FrameView(error: error, cached: await repo.cached(address));
});

/// The frame's name and owner as last seen, for its card while it loads.
final cachedFrameProvider = FutureProvider.family<CachedFrame?, FrameAddress>((ref, address) {
  ref.watch(framesProvider); // read again after signing out or in
  return ref.read(framesRepositoryProvider).cached(address);
});

/// Developer mode (app-flow §7.2): email sign-in on dev projects, extra details.
final devModeProvider = AsyncNotifierProvider<DevModeNotifier, bool>(DevModeNotifier.new);

class DevModeNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final raw = await ref.read(storeProvider).read('dev_mode');
    return raw == null ? AppConfig.devMode : jsonDecode(raw) as bool;
  }

  Future<void> set(bool on) async {
    await ref.read(storeProvider).write('dev_mode', jsonEncode(on));
    state = AsyncData(on);
  }
}

/// The last sign-in, reused for the next frame joined in this run ("Joining a second
/// frame reuses the same sign-in", app-flow §1.2). ID tokens last an hour.
final lastCredentialProvider = NotifierProvider<LastCredential, Credential?>(LastCredential.new);

class LastCredential extends Notifier<Credential?> {
  DateTime? _at;

  @override
  Credential? build() => null;

  void set(Credential c) {
    _at = DateTime.now();
    state = c;
  }

  /// Signed out, or choosing another account.
  void clear() {
    _at = null;
    state = null;
  }

  Credential? get fresh =>
      state != null && DateTime.now().difference(_at!) < const Duration(minutes: 50) ? state : null;
}
