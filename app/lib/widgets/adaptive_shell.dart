import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import 'frame_card.dart';
import 'more_frames_card.dart';

/// Two panes from 900 px wide, otherwise the phone layout (app-flow §2.3). Chosen
/// by window width only, never by platform.
class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  static const breakpoint = 900.0;

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= breakpoint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isWide(context)) return child;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 300, child: _Sidebar(location: location)),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final frames = ref.watch(framesProvider).value ?? [];
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(l.appTitle, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(l.albums.toUpperCase(), style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.8)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final f in frames)
                    FrameCard(
                      f,
                      dense: true,
                      selected: location == '/frame/${f.ref}',
                      onTap: () => context.go('/frame/${f.ref}'),
                    ),
                  Align(alignment: Alignment.centerLeft, child: AddMenuButton(label: l.setUpOrJoin)),
                  const Padding(padding: EdgeInsets.fromLTRB(4, 8, 4, 0), child: MoreFramesCard()),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(l.account),
              selected: location == '/account',
              onTap: () => context.go('/account'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
