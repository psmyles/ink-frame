import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/frame_link.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'loading.dart';
import 'status_line.dart';

/// A frame on Home (app-flow §4.1): name, "Set up by …" when it isn't yours, status.
class FrameCard extends ConsumerWidget {
  const FrameCard(this.address, {super.key, this.onTap, this.selected = false, this.dense = false});

  final FrameAddress address;
  final VoidCallback? onTap;
  final bool selected;

  /// Sidebar variant: no card border, tighter.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final view = ref.watch(frameViewProvider(address));

    final body = switch (view) {
      AsyncData(:final value) => _content(context, l, value),
      AsyncError() => Text(l.somethingWrong),
      _ => _Loading(name: ref.watch(cachedFrameProvider(address)).value?.name, dense: dense),
    };

    final child = Padding(padding: EdgeInsets.all(dense ? 12 : 16), child: body);
    if (dense) {
      return Material(
        color: selected ? theme.colorScheme.surfaceContainerHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: child),
      );
    }
    return Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: child));
  }

  Widget _content(BuildContext context, AppLocalizations l, FrameView v) {
    final theme = Theme.of(context);
    final summary = v.summary;
    final ownerName = summary?.owner.displayName ?? v.cached?.ownerName;
    final isMine = summary?.isMine ?? v.cached?.isMine ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          v.name ?? l.unknownFrame,
          style: (dense ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (!isMine && ownerName != null) ...[
          const SizedBox(height: 2),
          Text(l.setUpBy(ownerName), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        SizedBox(height: dense ? 6 : 10),
        StatusLine(v),
      ],
    );
  }
}

/// While the frame is read: its name from last time (a placeholder bar if none)
/// and "Loading…", so a slow connection doesn't look frozen.
class _Loading extends StatelessWidget {
  const _Loading({required this.name, required this.dense});

  final String? name;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (dense ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name != null)
          Text(name!, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)
        else
          Container(
            width: 140,
            height: 20,
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
          ),
        SizedBox(height: dense ? 6 : 10),
        SizedBox(height: 20, child: AfterDelay(child: LoadingLine(AppLocalizations.of(context).loading, size: 14))),
      ],
    );
  }
}
