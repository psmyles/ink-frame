import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

final _versionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// Account (app-flow §7.2). Phase 3a: frames on this device, sign out, developer
/// mode (7 taps on the version). Name, another device and delete come in 3d.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  var _taps = 0;

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
    await ref.read(framesProvider.notifier).signOutAll();
    if (mounted) context.go('/welcome');
  }

  void _versionTap() {
    if (ref.read(devModeProvider).value ?? false) return;
    if (++_taps >= 7) {
      ref.read(devModeProvider.notifier).set(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).developerModeOn)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final frames = ref.watch(framesProvider).value ?? [];
    final devMode = ref.watch(devModeProvider).value ?? false;
    final version = ref.watch(_versionProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l.account)),
      body: ListView(
        children: [
          if (frames.isNotEmpty) ...[
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
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l.version(version)),
            onTap: _versionTap,
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
}
