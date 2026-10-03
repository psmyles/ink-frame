import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../widgets/adaptive_shell.dart';
import '../../widgets/frame_card.dart';
import '../../widgets/frame_mark.dart';
import '../../widgets/loading.dart';

/// Every frame you're on, whoever set it up (app-flow D1, §2.2). On a wide window
/// the sidebar lists them, so this is only the "choose a frame" pane.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(framesProvider);
    // Still reading this device's frames (a moment at start): not "no frames yet".
    final loading = Center(child: AfterDelay(child: LoadingLine(l.loadingFrames)));
    if (AdaptiveShell.isWide(context)) return list.hasValue ? _ChooseFrame(text: l.chooseFrame) : Scaffold(body: loading);

    final frames = list.value ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          const AddMenuButton(),
          IconButton(
            tooltip: l.account,
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/account'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !list.hasValue
          ? loading
          : frames.isEmpty
          ? const NoFrames()
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(frameViewProvider),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: frames.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => FrameCard(
                  frames[i],
                  onTap: () => context.push('/frame/${frames[i].ref}'),
                ),
              ),
            ),
    );
  }
}

/// "+" in the header: Set up a frame / Join with an invite.
class AddMenuButton extends StatelessWidget {
  const AddMenuButton({super.key, this.label});

  /// Shows a text button (sidebar) instead of an icon.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.add_photo_alternate_outlined), onPressed: () => context.push('/setup'), child: Text(l.setUpFrame)),
        MenuItemButton(leadingIcon: const Icon(Icons.link), onPressed: () => context.push('/join'), child: Text(l.joinWithInvite)),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        return label == null
            ? IconButton(tooltip: l.setUpOrJoin, icon: const Icon(Icons.add), onPressed: toggle)
            : TextButton.icon(onPressed: toggle, icon: const Icon(Icons.add), label: Text(label!));
      },
    );
  }
}

class NoFrames extends StatelessWidget {
  const NoFrames({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: FrameMark(size: 88)),
              const SizedBox(height: 20),
              Text(l.noFramesYet, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(l.noFramesBody, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => context.push('/join'), child: Text(l.invited)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => context.push('/setup'), child: Text(l.setUpFrame)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChooseFrame extends StatelessWidget {
  const _ChooseFrame({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
