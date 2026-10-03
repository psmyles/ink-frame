import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/frame_link.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/frame_admin.dart';
import '../../state/photos.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/formatting.dart';
import '../../widgets/side_panel.dart';

/// Storage (app-flow §5.3): the frame's use against its limit, and by person (the
/// owner sees everyone; others see themselves).
class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key, required this.address});

  final FrameAddress address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final usage = ref.watch(usageProvider(address));
    return Scaffold(
      appBar: PanelAppBar(title: l.storage),
      body: switch (usage) {
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(usageProvider(address).future),
            child: _Body(address: address, usage: value),
          ),
        AsyncError() => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l.somethingWrong),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => ref.invalidate(usageProvider(address)), child: Text(l.tryAgain)),
            ]),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.address, required this.usage});

  final FrameAddress address;
  final Usage usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final names = ref.watch(memberNamesProvider(address)).value ?? const {};
    final me = ref.watch(frameViewProvider(address)).value?.summary?.me.userId;
    final barColor = usage.full || usage.nearlyFull ? context.ink.warning : theme.colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l.storageUsed(formatBytes(usage.frame.bytes, locale), formatBytes(usage.limitBytes, locale)),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: usage.fraction, minHeight: 12, color: barColor),
        ),
        const SizedBox(height: 8),
        Text(
          [l.photoCount(usage.frame.images), if (usage.frame.maxBytes == null) l.freePlan].join(' · '),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Text(l.storageByPerson, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        for (final u in [...usage.users]..sort((a, b) => b.bytes.compareTo(a.bytes)))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(_initial(u.userId == me ? l.youBadge : names[u.userId] ?? '?'))),
            title: Text(u.userId == me ? l.youBadge : names[u.userId] ?? l.someoneWhoLeft),
            subtitle: Text('${l.photoCount(u.images)} · ${formatBytes(u.bytes, locale)}'),
          ),
        const SizedBox(height: 16),
        Text(l.storageNote, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  static String _initial(String name) => name.isEmpty ? '?' : name.characters.first.toUpperCase();
}
