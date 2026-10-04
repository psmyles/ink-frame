import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_error.dart';
import '../data/backend_bundle.dart';
import '../data/frame_connection.dart';
import '../data/frame_link.dart';
import '../data/platform_api.dart';
import '../data/platform_auth.dart';
import '../data/provisioner.dart';
import 'providers.dart';

final backendBundleProvider = FutureProvider<BackendBundle>((ref) => BackendBundle.load());

final platformAuthProvider = Provider<PlatformAuth>((ref) => PlatformAuth(ref.watch(storeProvider)));

/// Whether a Supabase account is connected on this device (invalidate after changes).
final platformConnectedProvider = FutureProvider<bool>((ref) => ref.watch(platformAuthProvider).isConnected);

final provisionerProvider = FutureProvider<Provisioner>((ref) async {
  final auth = ref.watch(platformAuthProvider);
  return Provisioner(PlatformApi(auth.accessToken), await ref.watch(backendBundleProvider.future));
});

/// The wizard's steps, in order; each is saved when done.
enum SetupStep { create, ready, database, functions, auth, describe, owner }

/// What the owner sees: three rows of the checklist (app-flow §1.3).
enum SetupStage {
  storage({SetupStep.create, SetupStep.ready, SetupStep.database, SetupStep.functions}),
  signIn({SetupStep.auth, SetupStep.describe}),
  owner({SetupStep.owner});

  const SetupStage(this.steps);
  final Set<SetupStep> steps;
}

/// A frame being set up, saved under `setup` after every step.
class SetupPlan {
  const SetupPlan({
    required this.name,
    required this.modelId,
    required this.timezone,
    required this.displayName,
    this.ref,
    this.done = const {},
  });

  final String name;
  final String modelId;
  final String timezone;
  final String displayName;

  /// The project, once created.
  final String? ref;
  final Set<SetupStep> done;

  SetupPlan copyWith({String? ref, Set<SetupStep>? done}) => SetupPlan(
        name: name,
        modelId: modelId,
        timezone: timezone,
        displayName: displayName,
        ref: ref ?? this.ref,
        done: done ?? this.done,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'model_id': modelId,
        'timezone': timezone,
        'display_name': displayName,
        'ref': ref,
        'done': [for (final s in done) s.name],
      };

  factory SetupPlan.fromJson(Map<String, dynamic> j) => SetupPlan(
        name: j['name'] as String,
        modelId: j['model_id'] as String,
        timezone: j['timezone'] as String,
        displayName: j['display_name'] as String,
        ref: j['ref'] as String?,
        done: {for (final s in j['done'] as List) SetupStep.values.byName(s as String)},
      );
}

class SetupState {
  const SetupState({this.plan, this.running, this.needsSignIn = false, this.failed, this.error, this.finished});

  /// Null until "Set up" is pressed (or after finishing or cancelling).
  final SetupPlan? plan;
  final SetupStage? running;

  /// Waiting for the owner to sign in with Google/Apple (no recent sign-in to reuse).
  final bool needsSignIn;
  final SetupStage? failed;
  final Object? error;

  /// The new frame, once it's ready.
  final FrameAddress? finished;

  bool isDone(SetupStage s) => plan != null && plan!.done.containsAll(s.steps);

  /// Started earlier and stopped (closed app or failure) without an error showing.
  bool get resumable => plan != null && running == null && !needsSignIn && error == null && finished == null;
}

final setupProvider = AsyncNotifierProvider<SetupController, SetupState>(SetupController.new);

/// Runs the wizard (PLAN.md §6.2) step by step, saving progress after each, so a
/// failure or a closed app resumes where it stopped.
class SetupController extends AsyncNotifier<SetupState> {
  static const _key = 'setup';

  /// Auth may take a few seconds to pick up the new sign-in settings.
  static const signInAttempts = 6;
  static var signInRetryDelay = const Duration(seconds: 3);

  @override
  Future<SetupState> build() async {
    final raw = await ref.read(storeProvider).read(_key);
    return SetupState(plan: raw == null ? null : SetupPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>));
  }

  SetupState get _s => state.value ?? const SetupState();

  Future<void> _save(SetupPlan plan) async {
    await ref.read(storeProvider).write(_key, jsonEncode(plan.toJson()));
    state = AsyncData(SetupState(plan: plan, running: _s.running));
  }

  Future<void> start(SetupPlan plan) async {
    await _save(plan);
    await run();
  }

  /// Runs every step not done yet. [credential]: the owner's sign-in, if just made.
  Future<void> run({Credential? credential}) async {
    var plan = _s.plan;
    if (plan == null || _s.running != null) return;
    final p = await ref.read(provisionerProvider.future);
    final keepEmail = await ref.read(platformAuthProvider).isPersonalToken;
    SetupStage? stage;

    Future<void> step(SetupStep s, Future<void> Function(String ref) body) async {
      if (plan!.done.contains(s)) return;
      stage = SetupStage.values.firstWhere((g) => g.steps.contains(s));
      state = AsyncData(SetupState(plan: plan, running: stage));
      await body(plan!.ref!);
      plan = plan!.copyWith(done: {...plan!.done, s});
      await _save(plan!);
    }

    try {
      if (plan!.ref == null) {
        stage = SetupStage.storage;
        state = AsyncData(SetupState(plan: plan, running: stage));
        plan = plan!.copyWith(ref: await p.createProject(frameName: plan!.name, timezone: plan!.timezone), done: {SetupStep.create});
        await _save(plan!);
      }
      await step(SetupStep.ready, p.waitUntilReady);
      await step(SetupStep.database, p.installDatabase);
      await step(SetupStep.functions, p.deployFunctions);
      await step(SetupStep.auth, (r) => p.configureSignIn(r, keepEmail: keepEmail));
      await step(SetupStep.describe, (r) => p.describeFrame(r, name: plan!.name, modelId: plan!.modelId, timezone: plan!.timezone));

      // A dev-mode email sign-in only works where email sign-in was kept.
      final fresh = ref.read(lastCredentialProvider.notifier).fresh;
      final c = credential ?? (fresh is PasswordCredential && !keepEmail ? null : fresh);
      if (c == null) {
        state = AsyncData(SetupState(plan: plan, needsSignIn: true));
        return;
      }
      stage = SetupStage.owner;
      state = AsyncData(SetupState(plan: plan, running: stage));
      final address = await p.address(plan!.ref!);
      await _becomeOwner(p, plan!, address, c);
      await ref.read(storeProvider).delete(_key);
      state = AsyncData(SetupState(plan: plan!.copyWith(done: {...plan!.done, SetupStep.owner}), finished: address));
    } catch (e) {
      state = AsyncData(SetupState(plan: plan, failed: stage ?? SetupStage.storage, error: e));
    }
  }

  Future<void> _becomeOwner(Provisioner p, SetupPlan plan, FrameAddress address, Credential c) async {
    final repo = ref.read(framesRepositoryProvider);
    FrameConnection? conn;
    for (var i = 1; conn == null; i++) {
      try {
        conn = await repo.signIn(address, c);
      } on ApiException {
        if (i >= signInAttempts) rethrow;
        await Future<void>.delayed(signInRetryDelay);
      }
    }
    await p.setOwner(plan.ref!, userId: conn.userId!, displayName: plan.displayName);
    await repo.remember(address, await conn.loadSummary());
    await repo.add(address);
    await repo.setDisplayName(plan.displayName);
    unawaited(ref.read(frameDirectoryProvider).add([address], signedInWith: c));
    await ref.read(framesProvider.notifier).signedIn([address]);
  }

  /// The owner signs in (no recent sign-in to reuse), then setup continues.
  Future<void> signInAndContinue(Future<Credential> Function() signIn) async {
    final c = await signIn(); // SignInCancelled: stays waiting
    ref.read(lastCredentialProvider.notifier).set(c);
    state = AsyncData(SetupState(plan: _s.plan));
    await run(credential: c);
  }

  /// Gives up on a half-made frame: deletes its project (if made) and the progress.
  Future<void> cancel() async {
    final plan = _s.plan;
    if (plan?.ref != null && !plan!.done.contains(SetupStep.owner)) {
      try {
        await (await ref.read(provisionerProvider.future)).deleteFrame(plan.ref!);
      } catch (_) {
        // Already gone, or offline: it can be deleted from the Supabase dashboard.
      }
    }
    await ref.read(storeProvider).delete(_key);
    state = const AsyncData(SetupState());
  }

  /// After finishing: back to an empty form for the next frame.
  void reset() => state = const AsyncData(SetupState());
}
