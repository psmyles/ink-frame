import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/sign_in_service.dart';
import '../../data/api_error.dart';
import '../../data/frame_connection.dart';
import '../../data/platform_api.dart';
import '../../data/platform_auth.dart';
import '../../data/timezones.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/setup.dart';
import '../../widgets/formatting.dart';
import '../../widgets/sign_in_buttons.dart';
import '../../widgets/text_prompt.dart';
import '../settings/settings_screen.dart' show TimeZonePicker;

/// Set up a frame (app-flow §1.3): connect Supabase, pick the model, name it, then a
/// checklist that fills in while the frame's project is made (PLAN.md §6.2).
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _name = TextEditingController();
  final _yourName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _modelId;
  var _timezone = 'UTC';
  var _connecting = false;

  AppLocalizations get l => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    unawaited(_defaults());
  }

  Future<void> _defaults() async {
    final name = await ref.read(framesRepositoryProvider).lastDisplayName();
    String? zone;
    try {
      zone = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      // Not available (tests, some desktops): UTC.
    }
    if (!mounted) return;
    setState(() {
      if (name != null && _yourName.text.isEmpty) _yourName.text = name;
      if (zone != null && timeZones.contains(zone)) _timezone = zone;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _yourName, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      await ref.read(platformAuthProvider).connect();
      ref.invalidate(platformConnectedProvider);
    } on ConnectCancelled {
      // Stay put.
    } catch (e) {
      if (mounted) _snack(_devDetail(e is PlatformApiException && e.code == PlatformApiException.offline ? l.setupOffline : l.connectFailed, e));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _personalToken() async {
    final pat = await promptText(context, title: l.personalTokenTitle, initial: '', maxLength: 200);
    if (pat == null || pat.isEmpty) return;
    await ref.read(platformAuthProvider).usePersonalToken(pat);
    ref.invalidate(platformConnectedProvider);
  }

  Future<void> _start() async {
    await ref.read(setupProvider.notifier).start(SetupPlan(
          name: _name.text.trim(),
          modelId: _modelId!,
          timezone: _timezone,
          displayName: _yourName.text.trim(),
        ));
  }

  Future<void> _signIn(Future<Credential> Function() get) async {
    try {
      await ref.read(setupProvider.notifier).signInAndContinue(get);
    } on SignInCancelled {
      // Stay waiting.
    } catch (e) {
      if (mounted) _snack(_devDetail(l.setupSignInFailed, e));
    }
  }

  Future<void> _cancel(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.cancelSetupConfirm(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.continueSetup)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.cancelSetup)),
        ],
      ),
    );
    if (ok == true) await ref.read(setupProvider.notifier).cancel();
  }

  String _devDetail(String text, Object e) => (ref.read(devModeProvider).value ?? false) ? '$text\n$e' : text;

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.setUpFrame)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: switch (setup) {
                AsyncData(:final value) when value.plan != null => _progress(value),
                AsyncData() => _form(),
                _ => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Before "Set up": connect, model, name ──

  Widget _section(String number, String title, Widget child) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$number. $title', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _form() {
    final theme = Theme.of(context);
    final connected = ref.watch(platformConnectedProvider).value ?? false;
    final devMode = ref.watch(devModeProvider).value ?? false;
    final models = ref.watch(backendBundleProvider).value?.models ?? const [];
    _modelId ??= models.isEmpty ? null : models.first.id;
    final (city, region) = timeZoneParts(_timezone);
    final ready = connected && _modelId != null && _name.text.trim().isNotEmpty && _yourName.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(padding: const EdgeInsets.all(16), child: Text(l.setupExplain)),
        ),
        _section(
          '1',
          l.setupConnectTitle,
          connected
              ? Row(children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(l.supabaseConnected),
                ])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.tonal(
                      onPressed: _connecting ? null : _connect,
                      child: _connecting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Text(l.connectSupabase),
                    ),
                    const SizedBox(height: 8),
                    Text(l.connectSupabaseHint, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    if (devMode) TextButton(onPressed: _personalToken, child: Text(l.usePersonalToken)),
                  ],
                ),
        ),
        _section(
          '2',
          l.setupModelTitle,
          RadioGroup<String>(
            groupValue: _modelId,
            onChanged: (v) => setState(() => _modelId = v),
            child: Column(children: [
              for (final m in models)
                RadioListTile<String>(
                  value: m.id,
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.name),
                  subtitle: Text(l.modelSize(m.width, m.height)),
                ),
            ]),
          ),
        ),
        _section(
          '3',
          l.setupNameTitle,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l.frameName, hintText: l.frameNameHint),
                onChanged: (_) => setState(() {}),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.timeZone),
                subtitle: Text('$city · $region'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final zone = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => TimeZonePicker(current: _timezone)),
                  );
                  if (zone != null) setState(() => _timezone = zone);
                },
              ),
              TextField(
                controller: _yourName,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l.nameLabel, helperText: l.nameHeading),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: ready ? _start : null,
          child: Text(_name.text.trim().isEmpty ? l.setUpFrame : l.setUpNamed(_name.text.trim())),
        ),
      ],
    );
  }

  // ── After "Set up": the checklist ──

  Widget _progress(SetupState s) {
    final theme = Theme.of(context);
    final plan = s.plan!;
    if (s.finished != null) return _finished(plan.name, s.finished!.ref);

    Widget row(SetupStage stage, String title, {String? hint}) {
      final done = s.isDone(stage);
      final running = s.running == stage;
      final failed = s.failed == stage;
      final icon = done
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : running
              ? const SizedBox(width: 24, height: 24, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.5)))
              : failed
                  ? Icon(Icons.error, color: theme.colorScheme.error)
                  : Icon(Icons.radio_button_unchecked, color: theme.colorScheme.outline);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: icon,
        title: Text(title, style: TextStyle(fontWeight: running ? FontWeight.w600 : null)),
        subtitle: running && hint != null ? Text(hint) : null,
      );
    }

    final keepEmail = ref.watch(_personalTokenProvider).value ?? false;
    final methods = ref.read(signInServiceProvider).methods(devMode: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.settingUp(plan.name), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        row(SetupStage.storage, l.stageStorage, hint: l.stageStorageHint),
        row(SetupStage.signIn, l.stageSignIn),
        row(SetupStage.owner, l.stageOwner),
        if (s.needsSignIn) ...[
          const SizedBox(height: 8),
          Text(l.ownerSignInHint, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          SignInButtons(methods: methods, onPressed: _signIn),
          if (keepEmail) ..._passwordSignIn(),
        ],
        if (s.error != null) ..._failure(s.error!),
        if (s.resumable) ...[
          const SizedBox(height: 16),
          Text(l.setupStopped(plan.name)),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => ref.read(setupProvider.notifier).run(), child: Text(l.continueSetup)),
        ],
        if (s.running == null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: () => _cancel(plan.name), child: Text(l.cancelSetup)),
        ],
      ],
    );
  }

  /// Developer setups (personal access token) keep email sign-in.
  List<Widget> _passwordSignIn() => [
        const SizedBox(height: 8),
        Text(l.devSignIn, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: InputDecoration(labelText: l.email)),
        const SizedBox(height: 12),
        TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: l.password)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final email = _email.text.trim(), password = _password.text;
            if (email.isEmpty || password.length < 6) return;
            _signIn(() async => PasswordCredential(email, password));
          },
          child: Text(l.signIn),
        ),
      ];

  List<Widget> _failure(Object e) {
    final theme = Theme.of(context);
    final code = switch (e) {
      PlatformApiException(:final code) => code,
      ApiException() => 'sign_in',
      _ => null,
    };
    final message = switch (code) {
      PlatformApiException.projectLimit => l.setupLimit,
      PlatformApiException.reconnect || PlatformApiException.notConnected => l.setupReconnect,
      PlatformApiException.offline => l.setupOffline,
      'sign_in' => l.setupSignInFailed,
      _ => l.somethingWrong,
    };
    final reconnect = code == PlatformApiException.reconnect || code == PlatformApiException.notConnected;
    return [
      const SizedBox(height: 16),
      Text(_devDetail(message, e), style: TextStyle(color: theme.colorScheme.error)),
      const SizedBox(height: 16),
      if (code == PlatformApiException.projectLimit)
        OutlinedButton(
          onPressed: () => launchUrl(Uri.parse('https://supabase.com/dashboard/projects')),
          child: Text(l.openSupabase),
        ),
      if (reconnect)
        FilledButton(
          onPressed: _connecting
              ? null
              : () async {
                  await _connect();
                  if (await ref.read(platformAuthProvider).isConnected) await ref.read(setupProvider.notifier).run();
                },
          child: Text(l.connectSupabase),
        )
      else
        FilledButton(onPressed: () => ref.read(setupProvider.notifier).run(), child: Text(l.tryAgain)),
    ];
  }

  Widget _finished(String name, String frameRef) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(l.frameReady(name), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(l.frameReadyBody, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            ref.read(setupProvider.notifier).reset();
            context.go('/frame/$frameRef?connect=1');
          },
          child: Text(l.connectFrame),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            ref.read(setupProvider.notifier).reset();
            context.go('/frame/$frameRef');
          },
          child: Text(l.connectLater),
        ),
      ],
    );
  }
}

final _personalTokenProvider = FutureProvider.autoDispose<bool>((ref) => ref.watch(platformAuthProvider).isPersonalToken);
