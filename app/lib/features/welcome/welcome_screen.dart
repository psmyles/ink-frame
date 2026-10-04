import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/sign_in_service.dart';
import '../../data/api_error.dart';
import '../../data/frame_connection.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../widgets/frame_mark.dart';
import '../../widgets/password_sign_in.dart';
import '../../widgets/paste_link.dart';
import '../../widgets/sign_in_buttons.dart';

/// First run (app-flow §1.1): sign in first. The frames your account is on come
/// back by themselves (the directory, §1.4); with none, set up a frame or join one
/// with an invite, which then use the same sign-in.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  /// Signed in, with no frames found: set up or join.
  var _signedIn = false;
  var _busy = false;
  String? _error;

  /// The directory was asked and listed no frames for this account.
  var _checked = false;

  /// Why the account's frames couldn't be looked up (offline, the directory down).
  ApiException? _notChecked;

  @override
  void initState() {
    super.initState();
    // Back here with a recent sign-in (e.g. after leaving your last frame).
    _signedIn = ref.read(lastCredentialProvider.notifier).fresh != null;
  }

  AppLocalizations get l => AppLocalizations.of(context);

  Future<void> _signIn(Future<Credential> Function() get) => _run(() async {
        final credential = await get();
        ref.read(lastCredentialProvider.notifier).set(credential);
        await _findFrames(credential);
      });

  /// Looks again with the same sign-in, or asks for a new one once it's too old.
  Future<void> _retry() async {
    final fresh = ref.read(lastCredentialProvider.notifier).fresh;
    if (fresh == null) {
      setState(() => _signedIn = false);
      return;
    }
    await _run(() => _findFrames(fresh));
  }

  void _differentAccount() {
    ref.read(lastCredentialProvider.notifier).clear();
    unawaited(ref.read(signInServiceProvider).signOut());
    setState(() {
      _signedIn = false;
      _checked = false;
      _error = null;
      _notChecked = null;
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on SignInCancelled {
      // Stay put, no error.
    } catch (e) {
      if (mounted) setState(() => _error = _devDetail(l.somethingWrong, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks the directory which frames this account is on and signs in to each
  /// (app-flow §1.4); Home if any. Dev-mode email accounts aren't in the directory.
  Future<void> _findFrames(Credential credential) async {
    final directory = ref.read(frameDirectoryProvider);
    ApiException? problem;
    var checked = false;
    if (credential is IdTokenCredential && directory.available) {
      try {
        final frames = await directory.signIn(credential);
        checked = true;
        final skipped = await ref.read(framesRepositoryProvider).signInAll(frames, credential);
        unawaited(directory.remove(skipped));
        await ref.read(framesProvider.notifier).signedIn(frames);
        if (skipped.length < frames.length) {
          if (mounted) context.go('/home');
          return;
        }
      } on ApiException catch (e) {
        problem = e;
        // Some may have been signed in to before one failed: then it's Home after all.
        await ref.read(framesProvider.notifier).reload();
      }
    }
    if (!mounted) return;
    setState(() {
      _signedIn = true;
      _checked = checked && problem == null;
      _notChecked = problem;
    });
  }

  String _problemText(ApiException e) => switch (e.code) {
        ApiException.offline => l.findOffline,
        ApiException.asleep => l.asleepJoin,
        _ => _devDetail(l.findFailed, e),
      };

  String _devDetail(String text, Object e) =>
      (ref.read(devModeProvider).value ?? false) ? '$text\n$e' : text;

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_signedIn),
                  child: _signedIn ? _choose() : _welcome(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return PasteLinkShortcut(
      onLink: (link) => context.push(Uri(path: '/join', queryParameters: {'link': link}).toString()),
      child: page,
    );
  }

  Widget _welcome() {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final devMode = ref.watch(devModeProvider).value ?? false;
    final methods = ref.read(signInServiceProvider).methods(devMode: devMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: FrameMark(size: 120)),
        const SizedBox(height: 28),
        Text(l.appTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(l.tagline, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.merge(muted)),
        const SizedBox(height: 40),
        if (methods.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 20), child: Text(l.noSignInMethods, style: muted)),
        SignInButtons(methods: methods, onPressed: _signIn, busy: _busy),
        if (methods.contains(SignInMethod.password))
          PasswordSignIn(busy: _busy, onSignIn: (c) => _signIn(() async => c)),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 12),
              Flexible(child: Text(l.findingFrames)),
            ]),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 16),
        Text(l.signInExplain, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.merge(muted)),
      ],
    );
  }

  Widget _choose() {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final problem = _notChecked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: FrameMark(size: 88)),
        const SizedBox(height: 20),
        if (problem == null) ...[
          Text(l.noFramesYet, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_checked ? l.noFramesOnAccount : l.noFramesBody, textAlign: TextAlign.center, style: muted),
        ] else ...[
          Text(_problemText(problem), textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
          TextButton(onPressed: _busy ? null : _retry, child: Text(l.tryAgain)),
          const SizedBox(height: 8),
          Text(l.noFramesBody, textAlign: TextAlign.center, style: muted),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: _busy ? null : () => context.push('/join'), child: Text(l.invited)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _busy ? null : () => context.push('/setup'), child: Text(l.setUpFrame)),
        const SizedBox(height: 20),
        TextButton(onPressed: _busy ? null : _differentAccount, child: Text(l.differentAccount)),
      ],
    );
  }
}
