import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/frame_link.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/photos.dart';
import '../../state/providers.dart';

/// Full-size photos, swipe (or arrow keys) between them, delete (app-flow §3.6).
class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key, required this.address, required this.initial});

  final FrameAddress address;
  final int initial;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  late final _pages = PageController(initialPage: widget.initial);
  late var _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta, int count) {
    final next = (_index + delta).clamp(0, count - 1);
    _pages.animateToPage(next, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  Future<void> _delete(FrameImage image) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.deleteConfirm(1)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    final left = (ref.read(photosProvider(widget.address)).value?.length ?? 1) - 1;
    await ref.read(photosProvider(widget.address).notifier).delete([image.id]);
    if (left == 0 && mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final images = ref.watch(photosProvider(widget.address)).value ?? const <FrameImage>[];
    final model = ref.watch(frameModelProvider(widget.address)).value;
    final summary = ref.watch(frameViewProvider(widget.address)).value?.summary;
    final names = ref.watch(memberNamesProvider(widget.address)).value ?? const {};
    if (images.isEmpty || model == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final index = _index.clamp(0, images.length - 1);
    final current = images[index];
    final mine = current.uploadedBy != null && current.uploadedBy == summary?.me.userId;
    final canDelete = summary != null && (summary.isMine || mine);
    final who = current.uploadedBy == null ? l.someoneWhoLeft : (mine ? l.you : names[current.uploadedBy] ?? '…');
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(current.createdAt.toLocal());

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1, images.length),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1, images.length),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l.photoOf(index + 1, images.length)),
            actions: [
              if (canDelete) IconButton(tooltip: l.delete, icon: const Icon(Icons.delete_outline), onPressed: () => _delete(current)),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: AspectRatio(
                        aspectRatio: model.aspect,
                        child: Consumer(builder: (context, ref, _) {
                          final bytes = ref.watch(displayBytesProvider((widget.address, images[i])));
                          return switch (bytes) {
                            AsyncData(:final value) => Image.memory(value, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true),
                            AsyncError() => Center(child: Text(l.couldntLoad)),
                            _ => const Center(child: CircularProgressIndicator()),
                          };
                        }),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(children: [
                  Text(l.addedBy(who, date), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(l.noReEdit, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
