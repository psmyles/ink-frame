import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/sign_in_service.dart';
import '../../data/api_error.dart';
import '../../data/frame_connection.dart';
import '../../data/frame_link.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import 'scan_screen.dart';

enum _Step { find, link, signIn, name }

/// Join with an invite, or sign in on a new device (app-flow §1.2, §1.4).
///
/// On a new device, signing in with Google/Apple asks the directory for your frames.
/// A link works too: an invite link (with a code) joins one frame; a "Use on another
/// device" link signs in to every frame in it that you're still on.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.initialLink, this.returning = false});

  final String? initialLink;

  /// Opened from "Already use Ink Frame? Sign in".
  final bool returning;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _linkField = TextEditingController();
  final _nameField = TextEditingController();
  final _emailField = TextEditingController();
  final _passwordField = TextEditingController();

  var _step = _Step.link;
  FrameLink? _link;
  Credential? _credential;
  String? _error;
  var _busy = false;
  String? _nameSuggestion;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialLink;
    if (widget.returning && initial == null && _canFind) _step = _Step.find;
    if (initial != null) {
      _linkField.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _submitLink());
    }
  }

  @override
  void dispose() {
    for (final c in [_linkField, _nameField, _emailField, _passwordField]) {
      c.dispose();
    }
    super.dispose();
  }

  AppLocalizations get l => AppLocalizations.of(context);

  /// The directory needs a Google or Apple sign-in (not dev-mode email).
  bool get _canFind =>
      ref.read(frameDirectoryProvider).available &&
      ref.read(signInServiceProvider).methods(devMode: false).isNotEmpty;

  /// New device: sign in, ask the directory for your frames, sign in to each.
  Future<void> _find(Future<IdTokenCredential> Function() get) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credential = await get();
      final directory = ref.read(frameDirectoryProvider);
      final List<FrameAddress> frames;
      try {
        frames = await directory.signIn(credential);
      } on ApiException catch (e) {
        setState(() => _error = e.code == ApiException.offline ? l.findOffline : _devDetail(l.findFailed, e));
        return;
      }
      ref.read(lastCredentialProvider.notifier).set(credential);
      final skipped = await ref.read(framesRepositoryProvider).signInAll(frames, credential);
      unawaited(directory.remove(skipped));
      await ref.read(framesProvider.notifier).signedIn(frames);
      if (!mounted) return;
      if (skipped.length == frames.length) {
        setState(() => _error = l.noFramesFound);
        return;
      }
      context.go('/home');
    } on SignInCancelled {
      // Stay put, no error.
    } on ApiException catch (e) {
      setState(() => _error = _message(e));
    } catch (e) {
      setState(() => _error = _devDetail(l.somethingWrong, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitLink() {
    final link = FrameLink.parse(_linkField.text);
    setState(() {
      _link = link;
      _error = link == null ? l.invalidLink : null;
      if (link != null) _step = _Step.signIn;
    });
    final fresh = ref.read(lastCredentialProvider.notifier).fresh;
    if (link != null && fresh != null) _signIn(() async => fresh);
  }

  /// Phones scan the QR code; computers paste the link.
  static bool get _canScan => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (raw == null || !mounted) return;
    _linkField.text = raw;
    _submitLink();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text case final text?) {
      _linkField.text = text.trim();
      _submitLink();
    }
  }

  Future<void> _signIn(Future<Credential> Function() get) async {
    final link = _link!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credential = await get();
      _credential = credential;
      final repo = ref.read(framesRepositoryProvider);
      if (link.isInvite) {
        await repo.signIn(link.frames.single, credential);
        ref.read(lastCredentialProvider.notifier).set(credential);
        final last = await repo.lastDisplayName();
        _nameSuggestion = credential is IdTokenCredential ? credential.name : null;
        if (last != null) _nameField.text = last;
        setState(() => _step = _Step.name);
      } else {
        final skipped = await repo.signInAll(link.frames, credential);
        ref.read(lastCredentialProvider.notifier).set(credential);
        final directory = ref.read(frameDirectoryProvider);
        unawaited(directory
            .add([for (final f in link.frames) if (!skipped.contains(f)) f], signedInWith: credential)
            .then((_) => directory.remove(skipped)));
        await ref.read(framesProvider.notifier).signedIn(link.frames);
        if (!mounted) return;
        if (skipped.length == link.frames.length) {
          setState(() => _error = l.noFramesOnLink);
          return;
        }
        if (skipped.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.skippedFrames(skipped.length))));
        }
        context.go('/home');
      }
    } on SignInCancelled {
      // Stay on the sign-in step, no error (app-flow §1.2).
    } on ApiException catch (e) {
      setState(() => _error = _message(e));
    } catch (e) {
      setState(() => _error = _devDetail(l.somethingWrong, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final link = _link!;
    final name = _nameField.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(framesRepositoryProvider).join(link.frames.single, link.code!, name);
      unawaited(ref.read(frameDirectoryProvider).add(link.frames, signedInWith: _credential));
      await ref.read(framesProvider.notifier).signedIn(link.frames);
      if (mounted) context.go('/frame/${link.frames.single.ref}?tip=1');
    } on ApiException catch (e) {
      setState(() => _error = _message(e));
    } catch (e) {
      setState(() => _error = _devDetail(l.somethingWrong, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(ApiException e) => switch (e.code) {
        'invalid_invite' => l.inviteInvalid,
        ApiException.offline => l.offline,
        ApiException.asleep => l.asleepJoin,
        _ => _devDetail(l.somethingWrong, e),
      };

  String _devDetail(String text, Object e) =>
      (ref.read(devModeProvider).value ?? false) ? '$text\n$e' : text;

  @override
  Widget build(BuildContext context) {
    final title = widget.returning && !(_link?.isInvite ?? false) ? l.signInTitle : l.joinTitle;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: switch (_step) {
                    _Step.find => _findStep(),
                    _Step.link => _linkStep(),
                    _Step.signIn => _signInStep(),
                    _Step.name => _nameStep(),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorText() => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );

  Widget _help(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _linkStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _help(widget.returning ? l.signInLinkHelp : l.joinLinkHelp),
          if (_canScan) ...[
            FilledButton.tonalIcon(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: Text(l.scanQr)),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _linkField,
            autofocus: !_canScan,
            keyboardType: TextInputType.url,
            autocorrect: false,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: l.pasteLinkLabel,
              hintText: l.pasteLinkHint,
              suffixIcon: IconButton(tooltip: l.paste, icon: const Icon(Icons.content_paste), onPressed: _paste),
            ),
            onSubmitted: (_) => _submitLink(),
          ),
          _errorText(),
          const SizedBox(height: 24),
          FilledButton(onPressed: _submitLink, child: Text(l.continueAction)),
        ],
      );

  /// Continue with Google / Apple, for the methods this build and platform offer.
  List<Widget> _providerButtons(List<SignInMethod> methods, void Function(Future<IdTokenCredential> Function()) onPressed) {
    final service = ref.read(signInServiceProvider);
    final apple = !kIsWeb && (Platform.isIOS || Platform.isMacOS) && methods.contains(SignInMethod.apple);
    return [
      if (methods.contains(SignInMethod.google))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => onPressed(service.google),
            icon: const Icon(Icons.account_circle_outlined),
            label: Text(l.continueWithGoogle),
          ),
        ),
      if (apple)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => onPressed(service.apple),
            icon: const Icon(Icons.apple),
            label: Text(l.continueWithApple),
          ),
        ),
      if (apple && Platform.isIOS) _help(l.appleHint),
    ];
  }

  Widget _findStep() {
    final methods = ref.read(signInServiceProvider).methods(devMode: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _help(l.findExplain),
        ..._providerButtons(methods, _find),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 12),
              Text(l.findingFrames),
            ]),
          ),
        _errorText(),
        const SizedBox(height: 24),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _step = _Step.link;
                    _error = null;
                  }),
          child: Text(l.useLinkInstead),
        ),
      ],
    );
  }

  Widget _signInStep() {
    final devMode = ref.watch(devModeProvider).value ?? false;
    final methods = ref.read(signInServiceProvider).methods(devMode: devMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _help(l.signInExplain),
        if (methods.isEmpty) _help(l.noSignInMethods),
        ..._providerButtons(methods, _signIn),
        if (methods.contains(SignInMethod.password)) ...[
          const SizedBox(height: 8),
          Text(l.devSignIn, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          TextField(
            controller: _emailField,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(labelText: l.email),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordField,
            obscureText: true,
            decoration: InputDecoration(labelText: l.password),
            onSubmitted: (_) => _passwordSignIn(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _passwordSignIn, child: Text(l.signIn)),
        ],
        if (_busy) const Padding(padding: EdgeInsets.only(top: 20), child: Center(child: CircularProgressIndicator())),
        _errorText(),
      ],
    );
  }

  void _passwordSignIn() {
    final email = _emailField.text.trim(), password = _passwordField.text;
    if (email.isEmpty || password.length < 6) return;
    _signIn(() async => PasswordCredential(email, password));
  }

  Widget _nameStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.nameHeading, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameField,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.nameLabel),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _join(),
          ),
          if (_nameSuggestion case final s? when _nameField.text.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                label: Text(s),
                onPressed: () => setState(() => _nameField.text = s),
              ),
            ),
          _errorText(),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || _nameField.text.trim().isEmpty ? null : _join,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(l.join),
          ),
        ],
      );
}
