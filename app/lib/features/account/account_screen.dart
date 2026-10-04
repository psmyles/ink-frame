import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../battery/background.dart';
import '../../data/api_error.dart';
import '../../data/frame_link.dart';
import '../../data/platform_api.dart';
import '../../state/setup.dart';
import '../settings/owner_tools.dart';
import '../../l10n/app_localizations.dart';
import '../../state/frame_admin.dart';
import '../../state/photos.dart';
import '../../state/providers.dart';
import '../../widgets/adaptive_shell.dart';
import '../../widgets/text_prompt.dart';

final _versionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// The name you go by: from a frame you're on, else the one you last joined with.
final _myNameProvider = FutureProvider<String?>((ref) async {
  for (final f in await ref.watch(framesProvider.future)) {
    final name = (await ref.watch(frameViewProvider(f).future)).summary?.me.displayName;
    if (name != null) return name;
  }
  return ref.read(framesRepositoryProvider).lastDisplayName();
});

/// Account (app-flow §7.2): your name, use on another device, the frames on this
/// device, sign out, delete my account, developer mode (7 taps on the version).
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  var _taps = 0;

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _signOut() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.signOutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.signOut)),
        ],
      ),
    );
    if (ok != true) return;
    unawaited(ref.read(frameDirectoryProvider).signOut());
    await ref.read(framesProvider.notifier).signOutAll();
    if (mounted) context.go('/welcome');
  }

  /// Changes your name on every frame you're on (`PATCH /me` on each).
  Future<void> _rename(String current) async {
    final l = AppLocalizations.of(context);
    final trimmed = await promptText(context, title: l.yourName, initial: current, hint: l.yourNameHint);
    if (trimmed == null) return;

    final failed = <String>[];
    for (final f in ref.read(framesProvider).value ?? const <FrameAddress>[]) {
      try {
        await ref.read(frameApiProvider(f)).updateMe(trimmed);
      } on ApiException {
        failed.add(ref.read(frameViewProvider(f)).value?.name ?? l.unknownFrame);
      }
      ref.invalidate(frameViewProvider(f));
      ref.invalidate(memberNamesProvider(f));
      ref.invalidate(membersProvider(f));
    }
    await ref.read(framesRepositoryProvider).setDisplayName(trimmed);
    ref.invalidate(_myNameProvider);
    if (mounted) _snack(failed.isEmpty ? l.nameUpdated : l.nameUpdateFailed(failed.join(', ')));
  }

  Future<void> _anotherDevice(List<FrameAddress> frames) async {
    final sheet = _AnotherDeviceSheet(link: FrameLink(frames).toHttps());
    if (AdaptiveShell.isWide(context)) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: sheet)),
      );
    } else {
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => sheet);
    }
  }

  /// Leaves every frame you joined (deleting your account on each) and deletes the
  /// frames you set up (app-flow §7.2; that needs your Supabase account connected).
  Future<void> _deleteAccount(List<FrameAddress> frames) async {
    final l = AppLocalizations.of(context);
    final views = {for (final f in frames) f: await ref.read(frameViewProvider(f).future)};
    String nameOf(FrameAddress f) => views[f]?.name ?? l.unknownFrame;
    final owned = [for (final f in frames) if (views[f]?.summary?.isMine ?? views[f]?.cached?.isMine ?? false) f];
    final joined = [for (final f in frames) if (!owned.contains(f)) f];
    if (!mounted) return;

    final deletePhotos = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(
        joined: [for (final f in joined) nameOf(f)],
        owned: [for (final f in owned) nameOf(f)],
      ),
    );
    if (deletePhotos == null || !mounted) return;
    if (owned.isNotEmpty && !await ensureConnected(context, ref)) return;

    final failed = <String>[];
    final deleted = <FrameAddress>[];
    for (final f in owned) {
      try {
        await (await ref.read(provisionerProvider.future)).deleteFrame(f.ref);
        await ref.read(framesProvider.notifier).remove(f);
        deleted.add(f);
      } on PlatformApiException {
        failed.add(nameOf(f));
      }
    }
    for (final f in joined) {
      try {
        await ref.read(frameApiProvider(f)).deleteMe(deletePhotos: deletePhotos);
        await ref.read(framesProvider.notifier).remove(f);
        deleted.add(f);
      } on ApiException {
        failed.add(nameOf(f));
      }
    }
    // The directory forgets you once you're on no frames.
    final directory = ref.read(frameDirectoryProvider);
    unawaited(failed.isEmpty ? directory.forget() : directory.remove(deleted));
    if (!mounted) return;
    if (failed.isNotEmpty) {
      _snack(l.deleteFailed(failed.join(', ')));
    } else if ((ref.read(framesProvider).value ?? []).isEmpty) {
      context.go('/welcome');
    }
  }

  void _versionTap() {
    if (ref.read(devModeProvider).value ?? false) return;
    if (++_taps >= 7) {
      ref.read(devModeProvider.notifier).set(true);
      _snack(AppLocalizations.of(context).developerModeOn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final frames = ref.watch(framesProvider).value ?? [];
    final devMode = ref.watch(devModeProvider).value ?? false;
    final version = ref.watch(_versionProvider).value ?? '';
    final name = ref.watch(_myNameProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l.account)),
      body: ListView(
        children: [
          if (frames.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(l.yourName),
              subtitle: Text(name ?? ''),
              trailing: const Icon(Icons.edit_outlined),
              onTap: name == null ? null : () => _rename(name),
            ),
            ListTile(
              leading: const Icon(Icons.devices_other_outlined),
              title: Text(l.anotherDevice),
              trailing: const Icon(Icons.qr_code),
              onTap: () => _anotherDevice(frames),
            ),
            _header(theme, l.onThisDevice),
            for (final f in frames)
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: Text(ref.watch(frameViewProvider(f)).value?.name ?? l.unknownFrame),
                subtitle: devMode ? Text(f.ref) : null,
              ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l.signOut),
              onTap: _signOut,
            ),
            const Divider(),
          ],
          if (devMode)
            SwitchListTile(
              secondary: const Icon(Icons.developer_mode),
              title: Text(l.developerMode),
              subtitle: Text(l.developerModeBody),
              value: true,
              onChanged: (v) => ref.read(devModeProvider.notifier).set(v),
            ),
          if (devMode && ref.watch(batteryWatchProvider).supported)
            ListTile(
              leading: const Icon(Icons.battery_alert_outlined),
              title: Text(l.checkBatteriesNow),
              subtitle: Text(l.checkBatteriesNowBody),
              onTap: () async {
                await checkBatteries(ref.read(batteryWatchProvider), ref.read(notificationsProvider));
                _snack(l.checkedBatteries);
              },
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l.version(version)),
            onTap: _versionTap,
          ),
          if (frames.isNotEmpty) ...[
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
              title: Text(l.deleteAccount, style: TextStyle(color: theme.colorScheme.error)),
              onTap: () => _deleteAccount(frames),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
}

/// QR and link with every frame's address, no invite codes (app-flow §1.4).
class _AnotherDeviceSheet extends StatelessWidget {
  const _AnotherDeviceSheet({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.anotherDevice, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(l.anotherDeviceExplain, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: QrImageView(data: link, backgroundColor: Colors.white, padding: const EdgeInsets.all(12), semanticsLabel: l.anotherDevice),
          ),
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (buttonContext) => FilledButton.icon(
            onPressed: () {
              final box = buttonContext.findRenderObject() as RenderBox?;
              SharePlus.instance.share(ShareParams(
                text: link,
                sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
              ));
            },
            icon: const Icon(Icons.share),
            label: Text(l.shareLink),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
          },
          icon: const Icon(Icons.link),
          label: Text(l.copyLink),
        ),
      ]),
    );
  }
}

/// Lists what happens, offers "Also delete my photos", and needs DELETE typed.
/// Returns whether to delete the photos, or null if cancelled.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.joined, required this.owned});

  final List<String> joined, owned;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  var _photos = false;
  var _typed = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ok = _typed.trim().toUpperCase() == l.deleteWord;
    return AlertDialog(
      title: Text(l.deleteAccount),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.owned.isNotEmpty) ...[
            Text(l.deleteOwnedBody),
            const SizedBox(height: 8),
            for (final n in widget.owned) Text('• $n', style: theme.textTheme.titleSmall),
            const SizedBox(height: 16),
          ],
          if (widget.joined.isNotEmpty) ...[
            Text(l.deleteAccountBody),
            const SizedBox(height: 8),
            for (final n in widget.joined) Text('• $n', style: theme.textTheme.titleSmall),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.deletePhotosToo),
              value: _photos,
              onChanged: (v) => setState(() => _photos = v ?? false),
            ),
          ],
          TextField(
            decoration: InputDecoration(labelText: l.typeDelete),
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) => setState(() => _typed = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
          onPressed: ok ? () => Navigator.pop(context, _photos) : null,
          child: Text(l.deleteAccountButton),
        ),
      ],
    );
  }
}
