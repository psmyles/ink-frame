import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_error.dart';
import '../../data/frame_link.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/status_line.dart';

/// One frame (app-flow §3–4). Phase 3a: status and owner, read-only; photos come in 3c.
class FrameScreen extends ConsumerStatefulWidget {
  const FrameScreen({super.key, required this.address, this.showTip = false});

  final FrameAddress address;
  final bool showTip;

  @override
  ConsumerState<FrameScreen> createState() => _FrameScreenState();
}

class _FrameScreenState extends ConsumerState<FrameScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.showTip) WidgetsBinding.instance.addPostFrameCallback((_) => _tip());
  }

  void _tip() {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.firstTip),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.gotIt))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(frameViewProvider(widget.address));
    final view = async.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(view?.name ?? ''),
        actions: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(frameViewProvider(widget.address)),
          ),
        ],
      ),
      body: view == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(frameViewProvider(widget.address)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  if (view.error != null) _Banner(view: view, address: widget.address),
                  if (view.summary case final s?) ...[
                    if (!s.isMine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(l.setUpBy(s.owner.displayName), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      ),
                    StatusLine(view),
                    const SizedBox(height: 6),
                    Text(l.checkHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 48),
                    Icon(Icons.photo_library_outlined, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(l.noPhotosYet, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(l.photosComing, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Asleep / removed / signed out (app-flow §10).
class _Banner extends ConsumerWidget {
  const _Banner({required this.view, required this.address});

  final FrameView view;
  final FrameAddress address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = view.name ?? l.unknownFrame;
    final error = view.error!;

    final (String text, Widget? action) = switch (error.code) {
      ApiException.asleep => (
          (view.cached?.isMine ?? false) ? l.asleepOwner(name) : l.asleepOther(name, view.cached?.ownerName ?? l.theOwner),
          null,
        ),
      ApiException.notMember => (
          l.removedFromFrame,
          OutlinedButton(
            onPressed: () async {
              await ref.read(framesProvider.notifier).remove(address);
              if (context.mounted) context.go('/home');
            },
            child: Text(l.removeFromDevice),
          ),
        ),
      ApiException.signedOut => (
          l.signedOutOfFrame,
          FilledButton(
            onPressed: () => context.push(Uri(path: '/join', queryParameters: {
              'mode': 'signin',
              'link': FrameLink([address]).toHttps(),
            }).toString()),
            child: Text(l.signInAgain),
          ),
        ),
      ApiException.offline => (l.offline, null),
      _ => (l.somethingWrong, null),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: context.ink.warning, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }
}
