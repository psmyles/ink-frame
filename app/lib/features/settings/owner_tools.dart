import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/frame_link.dart';
import '../../data/platform_api.dart';
import '../../data/platform_auth.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/setup.dart';

/// Whether this app has a newer backend for the frame (only when a Supabase account
/// is connected on this device; false if it can't tell).
final frameUpdateProvider = FutureProvider.autoDispose.family<bool, FrameAddress>((ref, a) async {
  if (!await ref.watch(platformConnectedProvider.future)) return false;
  try {
    return await (await ref.watch(provisionerProvider.future)).updateAvailable(a.ref);
  } on PlatformApiException {
    return false;
  }
});

/// Owner tools at the bottom of Settings (app-flow §4.4): the Supabase account on this
/// device, Update, Delete this frame. They use the owner's platform token.
class OwnerTools extends ConsumerWidget {
  const OwnerTools({super.key, required this.address, required this.frameName});

  final FrameAddress address;
  final String frameName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final connected = ref.watch(platformConnectedProvider).value ?? false;
    final update = ref.watch(frameUpdateProvider(address)).value ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(l.supabaseAccount),
          subtitle: Text(connected ? l.supabaseConnected : l.supabaseNotHere),
          trailing: connected ? null : TextButton(onPressed: () => connectSupabase(context, ref), child: Text(l.connect)),
        ),
        if (update)
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: Text(l.updateReady(frameName)),
            subtitle: Text(l.updateHint),
            trailing: FilledButton.tonal(onPressed: () => _update(context, ref), child: Text(l.update)),
          ),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
          title: Text(l.deleteAlbum, style: TextStyle(color: theme.colorScheme.error)),
          onTap: () => _delete(context, ref),
        ),
      ],
    );
  }

  Future<void> _update(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await withProgress(context, l.updatingAlbum(frameName), () async {
      await (await ref.read(provisionerProvider.future)).update(address.ref);
    });
    ref.invalidate(frameUpdateProvider(address));
    if (ok == null) {
      // New backend features (the low-battery notification's watch tokens) work now.
      await ref.read(batteryWatchProvider).updated(address);
      ref.invalidate(frameViewProvider(address));
    }
    messenger.showSnackBar(SnackBar(content: Text(ok == null ? l.updated(frameName) : _failure(l, ok, l.updateFailed(frameName)))));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    if (!await ensureConnected(context, ref) || !context.mounted) return;
    final confirmed = await showDialog<bool>(context: context, builder: (_) => _DeleteFrameDialog(frameName: frameName));
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final error = await withProgress(context, l.deletingAlbum(frameName), () async {
      await (await ref.read(provisionerProvider.future)).deleteFrame(address.ref);
    });
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(_failure(l, error, l.deleteAlbumFailed(frameName)))));
      return;
    }
    unawaited(ref.read(frameDirectoryProvider).remove([address]));
    await ref.read(framesProvider.notifier).remove(address);
    // Close the side sheet (or page) first: going Home doesn't remove a sheet.
    if (navigator.canPop()) navigator.pop();
    router.go('/home');
  }

  String _failure(AppLocalizations l, Object e, String fallback) => switch (e) {
        PlatformApiException(code: PlatformApiException.offline) => l.setupOffline,
        PlatformApiException(status: 403 || 404) => l.wrongSupabaseAccount(frameName),
        _ => fallback,
      };
}

/// "Connect Supabase" from anywhere (owner tools, wake up). Returns whether connected.
Future<bool> connectSupabase(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(platformAuthProvider).connect();
  } on ConnectCancelled {
    return false;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l.connectFailed)));
    return false;
  } finally {
    ref.invalidate(platformConnectedProvider);
  }
  return true;
}

Future<bool> ensureConnected(BuildContext context, WidgetRef ref) async =>
    await ref.read(platformConnectedProvider.future) || (context.mounted && await connectSupabase(context, ref));

/// Wakes an asleep frame (PLAN.md §6.4), owner only: ~3 minutes with a progress dialog.
Future<void> wakeUpFrame(BuildContext context, WidgetRef ref, FrameAddress address, String frameName) async {
  final l = AppLocalizations.of(context);
  if (!await ensureConnected(context, ref) || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final error = await withProgress(context, l.wakingUp(frameName), () async {
    await (await ref.read(provisionerProvider.future)).wakeUp(address.ref);
  });
  if (error != null) {
    messenger.showSnackBar(SnackBar(content: Text(switch (error) {
      PlatformApiException(code: PlatformApiException.offline) => l.setupOffline,
      PlatformApiException(status: 403 || 404) => l.wrongSupabaseAccount(frameName),
      _ => l.wakeUpFailed(frameName),
    })));
    return;
  }
  ref.invalidate(connectionProvider(address));
}

/// Runs [work] behind a dialog that can't be dismissed. Returns the error, if any.
Future<Object?> withProgress(BuildContext context, String text, Future<void> Function() work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 20),
          Expanded(child: Text(text)),
        ]),
      ),
    ),
  ));
  try {
    await work();
    return null;
  } catch (e) {
    return e;
  } finally {
    navigator.pop();
  }
}

/// Typed confirmation of the frame's name (app-flow §4.4).
class _DeleteFrameDialog extends StatefulWidget {
  const _DeleteFrameDialog({required this.frameName});

  final String frameName;

  @override
  State<_DeleteFrameDialog> createState() => _DeleteFrameDialogState();
}

class _DeleteFrameDialogState extends State<_DeleteFrameDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final matches = _typed.text.trim().toLowerCase() == widget.frameName.trim().toLowerCase();
    return AlertDialog(
      title: Text(l.deleteAlbum),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.deleteAlbumConfirm(widget.frameName)),
          const SizedBox(height: 16),
          TextField(
            controller: _typed,
            autofocus: true,
            decoration: InputDecoration(labelText: l.typeToConfirm(widget.frameName)),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          child: Text(l.delete),
        ),
      ],
    );
  }
}
