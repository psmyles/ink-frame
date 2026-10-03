import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_error.dart';
import '../../data/frame_link.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/frame_admin.dart';
import '../../state/providers.dart';
import '../../widgets/formatting.dart';

/// Connect with a code (developer, app-flow §6.3): a pairing token for
/// `frame_sim claim`, then waits until the hardware has claimed the frame. Pops
/// with true once it has.
class DevConnectScreen extends ConsumerStatefulWidget {
  const DevConnectScreen({super.key, required this.address, this.pollEvery = const Duration(seconds: 3)});

  final FrameAddress address;
  final Duration pollEvery;

  /// The frame_sim command line (run in tools/frame_sim).
  static String command(FrameAddress a, String token) {
    final host = Uri.parse(a.url).host;
    final target = host.endsWith('.supabase.co') ? '--ref ${a.ref}' : '--api ${a.url}/functions/v1';
    return 'dart run bin/frame_sim.dart claim $target --token $token';
  }

  @override
  ConsumerState<DevConnectScreen> createState() => _DevConnectScreenState();
}

class _DevConnectScreenState extends ConsumerState<DevConnectScreen> {
  PairingToken? _token;
  Frame? _before;
  Object? _error;
  var _connected = false;
  Timer? _poll;

  AppLocalizations get l => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    unawaited(_newCode());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _newCode() async {
    setState(() {
      _token = null;
      _error = null;
    });
    try {
      final view = await ref.read(frameViewProvider(widget.address).future);
      final token = await ref.read(frameApiProvider(widget.address)).createPairingToken();
      if (!mounted) return;
      setState(() {
        _before = view.summary?.frame;
        _token = token;
      });
      _poll?.cancel();
      _poll = Timer.periodic(widget.pollEvery, (_) => _check());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Connected once hardware is linked that wasn't before: a new `hw_id`, or the
  /// same one checking in again.
  Future<void> _check() async {
    ref.invalidate(frameViewProvider(widget.address));
    final f = (await ref.read(frameViewProvider(widget.address).future)).summary?.frame;
    if (!mounted || f == null || f.hwId == null) return;
    final b = _before;
    if (b == null || b.hwId != f.hwId || (f.lastSeenAt != null && f.lastSeenAt != b.lastSeenAt)) {
      _poll?.cancel();
      setState(() => _connected = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final token = _token;
    final name = ref.watch(frameViewProvider(widget.address)).value?.name ?? '';
    final command = token == null ? null : DevConnectScreen.command(widget.address, token.token);
    return Scaffold(
      appBar: AppBar(title: Text(l.connectWithCode)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_connected) ...[
            Icon(Icons.check_circle, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(l.frameConnected(name), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.done)),
          ] else if (_error != null) ...[
            Text('${l.somethingWrong}\n$_error', style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _newCode, child: Text(l.tryAgain)),
          ] else if (command == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text(l.devCodeExplain),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(command, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            ),
            Row(children: [
              Expanded(
                child: Text(
                  l.codeExpires(formatHhmm(context, toHhmm(TimeOfDay.fromDateTime(token!.expiresAt.toLocal())))),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: command));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                },
                icon: const Icon(Icons.copy),
                label: Text(l.copy),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 12),
              Expanded(child: Text(l.waitingForFrame)),
            ]),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _newCode, child: Text(l.newCode))),
          ],
        ],
      ),
    );
  }
}
