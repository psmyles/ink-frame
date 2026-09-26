import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/sign_in_service.dart';
import '../config/app_config.dart';
import '../data/api_error.dart';
import '../data/frame_connection.dart';
import '../data/frame_link.dart';
import '../data/frames_repository.dart';
import '../data/models.dart';
import '../data/secure_store.dart';

final storeProvider = Provider<KeyValueStore>((ref) => SecureStore());

final framesRepositoryProvider = Provider<FramesRepository>((ref) => FramesRepository(ref.watch(storeProvider)));

final signInServiceProvider = Provider<SignInService>((ref) => SignInService());

/// The frames on this device, in the order they were added.
final framesProvider = AsyncNotifierProvider<FramesNotifier, List<FrameAddress>>(FramesNotifier.new);

class FramesNotifier extends AsyncNotifier<List<FrameAddress>> {
  FramesRepository get _repo => ref.read(framesRepositoryProvider);

  @override
  Future<List<FrameAddress>> build() => _repo.load();

  Future<void> reload() async => state = AsyncData(await _repo.load());

  Future<void> remove(FrameAddress a) async {
    await _repo.remove(a);
    ref.invalidate(frameViewProvider(a));
    await reload();
  }

  Future<void> signOutAll() async {
    await _repo.signOutAll();
    ref.invalidate(frameViewProvider);
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
  final repo = ref.read(framesRepositoryProvider);
  try {
    final conn = await repo.ready(address);
    if (!conn.isSignedIn) {
      return FrameView(
        error: const ApiException(ApiException.signedOut, 'Not signed in.'),
        cached: await repo.cached(address),
      );
    }
    final summary = await conn.loadSummary();
    await repo.remember(address, summary);
    return FrameView(summary: summary);
  } on ApiException catch (e) {
    return FrameView(error: e, cached: await repo.cached(address));
  }
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

  Credential? get fresh =>
      state != null && DateTime.now().difference(_at!) < const Duration(minutes: 50) ? state : null;
}
