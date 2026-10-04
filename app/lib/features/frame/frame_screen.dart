import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_error.dart';
import '../../data/frame_link.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/frame_admin.dart';
import '../../state/photos.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../widgets/adaptive_shell.dart';
import '../../widgets/photo_tile.dart';
import '../../widgets/side_panel.dart';
import '../../widgets/status_line.dart';
import '../connect/connect_frame_screen.dart';
import '../people/people_screen.dart';
import '../prepare/prepare_screen.dart';
import '../prepare/source_photo.dart';
import '../settings/owner_tools.dart';
import '../settings/settings_screen.dart';
import '../storage/storage_screen.dart';
import 'reorder_screen.dart';
import 'viewer_screen.dart';

/// One frame (app-flow §3–4): status, the photo grid, adding, selecting, deleting.
class FrameScreen extends ConsumerStatefulWidget {
  const FrameScreen({super.key, required this.address, this.showTip = false, this.connectNow = false});

  final FrameAddress address;
  final bool showTip;

  /// Straight from setup's "Connect the frame".
  final bool connectNow;

  @override
  ConsumerState<FrameScreen> createState() => _FrameScreenState();
}

class _FrameScreenState extends ConsumerState<FrameScreen> {
  final _selected = <String>{};
  var _dragging = false;

  FrameAddress get _a => widget.address;

  @override
  void initState() {
    super.initState();
    if (widget.showTip) WidgetsBinding.instance.addPostFrameCallback((_) => _tip());
    if (widget.connectNow) WidgetsBinding.instance.addPostFrameCallback((_) => openConnectFrame(context, _a));
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

  Future<void> _refresh() async {
    ref.invalidate(frameViewProvider(_a));
    await ref.read(photosProvider(_a).notifier).refresh();
  }

  Future<void> _addPhotos([List<(String, Uint8List)>? given]) async {
    final picked = given ?? await pickPhotos();
    if (picked.isEmpty || !mounted) return;
    final decoded = await openPhotos(context, picked);
    if (decoded.isEmpty || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PrepareScreen(address: _a, photos: decoded),
    ));
  }

  Future<void> _dropped(DropDoneDetails d) async {
    setState(() => _dragging = false);
    final files = [
      for (final f in d.files)
        if (isPhotoFile(f.name)) (f.name, await f.readAsBytes()),
    ];
    await _addPhotos(files);
  }

  bool _canDelete(FrameSummary s, List<FrameImage> images) =>
      s.isMine || images.where((i) => _selected.contains(i.id)).every((i) => i.uploadedBy == s.me.userId);

  Future<void> _deleteSelected(FrameSummary s, List<FrameImage> images) async {
    final l = AppLocalizations.of(context);
    if (!_canDelete(s, images)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.cantDeleteOthers)));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.deleteConfirm(_selected.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    final ids = [..._selected];
    setState(_selected.clear);
    try {
      await ref.read(photosProvider(_a).notifier).delete(ids);
    } on ApiException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.somethingWrong)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final view = ref.watch(frameViewProvider(_a)).value;
    final summary = view?.summary;
    final images = ref.watch(photosProvider(_a));
    final queue = ref.watch(uploadQueueProvider(_a));
    final model = ref.watch(frameModelProvider(_a)).value;
    final selecting = _selected.isNotEmpty;
    final list = images.value ?? const <FrameImage>[];

    ref.listen(uploadQueueProvider(_a), (_, _) {
      final q = ref.read(uploadQueueProvider(_a).notifier);
      if (q.duplicates > 0) {
        final n = q.duplicates;
        q.duplicates = 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.alreadyOnFrame(n))));
      }
    });

    final canReorder = summary != null && summary.isMine && summary.frame.inOrder && list.length > 1;
    final wide = AdaptiveShell.isWide(context);

    final body = view == null
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  sliver: SliverToBoxAdapter(child: _Header(view: view, address: _a, queue: queue)),
                ),
                if (summary != null && model != null)
                  if (list.isEmpty && queue.isEmpty && images.hasValue)
                    SliverFillRemaining(hasScrollBody: false, child: _Empty(onAdd: _addPhotos))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 240,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: model.aspect,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          childCount: list.length + queue.length,
                          (context, i) {
                            if (i >= list.length) return UploadTile(address: _a, item: queue[i - list.length], model: model);
                            final image = list[i];
                            return PhotoTile(
                              address: _a,
                              image: image,
                              selected: _selected.contains(image.id),
                              onTap: () {
                                if (selecting) {
                                  setState(() => _selected.contains(image.id) ? _selected.remove(image.id) : _selected.add(image.id));
                                } else {
                                  Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => ViewerScreen(address: _a, initial: i),
                                  ));
                                }
                              },
                              onLongPress: () => setState(() => _selected.add(image.id)),
                            );
                          },
                        ),
                      ),
                    ),
              ],
            ),
          );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(_selected.clear),
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (summary != null && selecting) _deleteSelected(summary, list);
        },
        // The Mac's delete key.
        const SingleActivator(LogicalKeyboardKey.backspace): () {
          if (summary != null && selecting) _deleteSelected(summary, list);
        },
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () => setState(() => _selected.addAll(list.map((i) => i.id))),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => setState(() => _selected.addAll(list.map((i) => i.id))),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: selecting
              ? AppBar(
                  leading: IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(_selected.clear),
                  ),
                  title: Text(l.selected(_selected.length)),
                  actions: [
                    IconButton(
                      tooltip: l.delete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: summary == null ? null : () => _deleteSelected(summary, list),
                    ),
                  ],
                )
              : AppBar(
                  title: Text(view?.name ?? ''),
                  actions: [
                    if (canReorder)
                      IconButton(
                        tooltip: l.reorder,
                        icon: const Icon(Icons.swap_vert),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => ReorderScreen(address: _a),
                        )),
                      ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
                      icon: const Icon(Icons.refresh),
                      onPressed: _refresh,
                    ),
                    if (summary != null) ...[
                      IconButton(
                        tooltip: l.people,
                        icon: const Icon(Icons.people_outline),
                        onPressed: () => openPanel<void>(context, (_) => PeopleScreen(address: _a)),
                      ),
                      IconButton(
                        tooltip: l.settings,
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => openPanel<void>(context, (_) => SettingsScreen(address: _a)),
                      ),
                    ],
                    if (wide && summary != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                          onPressed: _addPhotos,
                          icon: const Icon(Icons.add),
                          label: Text(l.addPhotos),
                        ),
                      ),
                  ],
                ),
          floatingActionButton: !wide && summary != null && !selecting
              ? FloatingActionButton(tooltip: l.addPhotos, onPressed: _addPhotos, child: const Icon(Icons.add))
              : null,
          body: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: summary == null ? null : _dropped,
            child: Stack(children: [
              body,
              if (_dragging && view?.name != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    child: Center(
                      child: Card(
                        child: Padding(padding: const EdgeInsets.all(20), child: Text(l.dropHere(view!.name!))),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.view, required this.address, required this.queue});

  final FrameView view;
  final FrameAddress address;
  final List<UploadItem> queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = view.summary;
    final failed = queue.where((i) => i.status == UploadStatus.failed).toList();
    final usage = s == null ? null : ref.watch(usageProvider(address)).value;
    final full = failed.any((i) => i.error?.code == 'quota_exceeded') || (usage?.full ?? false);
    final name = view.name ?? l.unknownFrame;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (view.error != null) _Banner(view: view, address: address),
        if (s != null) ...[
          if (!s.isMine)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.setUpBy(s.owner.displayName), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
          StatusLine(view),
          if (s.frame.connected) ...[
            const SizedBox(height: 6),
            Text(l.checkHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ] else if (s.isMine) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => openConnectFrame(context, address),
              icon: const Icon(Icons.bluetooth),
              label: Text(l.connectFrame),
            ),
          ],
        ],
        if (full)
          _Notice(
            text: l.storageFull(name),
            action: TextButton(onPressed: () => _openStorage(context, address), child: Text(l.seeStorage)),
          )
        else if (failed.isNotEmpty)
          _Notice(
            text: l.uploadsFailed(failed.length),
            action: TextButton(
              onPressed: () => ref.read(uploadQueueProvider(address).notifier).retryAll(),
              child: Text(l.retryAll),
            ),
          )
        else if (usage != null && usage.nearlyFull)
          _Notice(
            text: l.storageGettingFull(name, (usage.fraction * 100).round()),
            action: TextButton(onPressed: () => _openStorage(context, address), child: Text(l.seeStorage)),
          ),
      ],
    );
  }
}

void _openStorage(BuildContext context, FrameAddress address) =>
    openPanel<void>(context, (_) => StorageScreen(address: address));

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: context.ink.warning, width: 4)),
        ),
        child: Row(children: [Expanded(child: Text(text)), ?action]),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(l.noPhotosYet, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l.noPhotosBody, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(l.addPhotos)),
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
      ApiException.asleep => (view.cached?.isMine ?? false)
          ? (l.asleepOwner(name), FilledButton(onPressed: () => wakeUpFrame(context, ref, address, name), child: Text(l.wakeUp)))
          : (l.asleepOther(name, view.cached?.ownerName ?? l.theOwner), null),
      ApiException.notMember => (l.removedFromFrame, _removeButton(context, ref, l)),
      ApiException.gone => (l.frameGone(name), _removeButton(context, ref, l)),
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

  Widget _removeButton(BuildContext context, WidgetRef ref, AppLocalizations l) => OutlinedButton(
        onPressed: () async {
          await ref.read(framesProvider.notifier).drop(address);
          if (context.mounted) context.go('/home');
        },
        child: Text(l.removeFromDevice),
      );
}
