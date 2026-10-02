import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/frame_link.dart';
import '../../imaging/resize.dart';
import '../../l10n/app_localizations.dart';
import '../../state/photos.dart';
import 'photo_editor.dart';
import 'prepare_session.dart';
import 'source_photo.dart';

/// Decodes picked files, telling the person about any that couldn't be opened.
Future<List<SourcePhoto>> openPhotos(BuildContext context, List<(String, Uint8List)> picked) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text(l.openingPhotos), duration: const Duration(seconds: 30)));
  final decoded = <SourcePhoto>[];
  for (final (name, bytes) in picked) {
    final p = await SourcePhoto.decode(name, bytes);
    if (p != null) decoded.add(p);
  }
  messenger.hideCurrentSnackBar();
  if (decoded.length < picked.length) {
    messenger.showSnackBar(SnackBar(content: Text(l.cantOpenPhotos(picked.length - decoded.length))));
  }
  return decoded;
}

/// Prepare (app-flow §3.3). Several photos: an overview of how each will look on
/// the frame; tap one to edit it. A single photo opens straight in the editor.
class PrepareScreen extends ConsumerStatefulWidget {
  const PrepareScreen({super.key, required this.address, required this.photos});

  final FrameAddress address;
  final List<SourcePhoto> photos;

  @override
  ConsumerState<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends ConsumerState<PrepareScreen> {
  PrepareSession? _session;
  late final bool _single = widget.photos.length == 1;

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  PrepareSession _sessionFor(FrameModel model) =>
      _session ??= PrepareSession(model, widget.photos, ref.read(previewEngineProvider));

  void _upload(PrepareSession s) {
    ref.read(uploadQueueProvider(widget.address).notifier).addAll([for (final it in s.items) s.jobFor(it)]);
    Navigator.of(context).pop();
  }

  Future<void> _confirmLeave() async {
    final l = AppLocalizations.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.leaveTitle),
        content: Text(l.leaveBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.keepEditing)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.leave)),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _edit(PrepareSession s, int index) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PhotoEditorScreen(session: s, index: index),
      ));

  Future<void> _addMore(PrepareSession s) async {
    final picked = await pickPhotos();
    if (picked.isEmpty || !mounted) return;
    final decoded = await openPhotos(context, picked);
    if (decoded.isNotEmpty) s.add(decoded);
  }

  void _remove(PrepareSession s, PrepItem it) {
    if (s.items.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    s.remove(it);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final model = ref.watch(frameModelProvider(widget.address)).value;
    final s = model == null ? null : _sessionFor(model);

    return ListenableBuilder(
      listenable: s ?? const AlwaysStoppedAnimation(0),
      builder: (context, _) {
        // Ask before throwing away more than a quick pick.
        final careful = s != null && (s.items.length > 1 || s.items.any((i) => !i.isOriginal));
        return PopScope(
          canPop: !careful,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave();
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: l.cancel,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              // The count is on Upload; a short title keeps both visible in narrow windows.
              title: FittedBox(fit: BoxFit.scaleDown, child: Text(l.prepareTitle)),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                    onPressed: s == null ? null : () => _upload(s),
                    icon: const Icon(Icons.upload),
                    label: Text(l.uploadCount(s?.items.length ?? widget.photos.length)),
                  ),
                ),
              ],
            ),
            body: switch (s) {
              null => const Center(child: CircularProgressIndicator()),
              _ when _single && s.items.isNotEmpty => PhotoEditor(session: s, item: s.items.first),
              _ => _Overview(
                  session: s,
                  onEdit: (i) => _edit(s, i),
                  onRemove: (it) => _remove(s, it),
                  onAddMore: () => _addMore(s),
                ),
            },
          ),
        );
      },
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.session, required this.onEdit, required this.onRemove, required this.onAddMore});

  final PrepareSession session;
  final ValueChanged<int> onEdit;
  final ValueChanged<PrepItem> onRemove;
  final VoidCallback onAddMore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = session.items;
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        sliver: SliverToBoxAdapter(
          // One line; shrinks rather than wrapping on the narrowest phones.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              l.prepareHint,
              maxLines: 1,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 440,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: session.model.aspect,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _PreviewCard(
            key: ObjectKey(items[i]),
            session: session,
            item: items[i],
            onTap: () => onEdit(i),
            onRemove: () => onRemove(items[i]),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onAddMore,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(l.addMore),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({super.key, required this.session, required this.item, required this.onTap, required this.onRemove});

  final PrepareSession session;
  final PrepItem item;
  final VoidCallback onTap, onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final look = item.preview;
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(10),
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Stack(fit: StackFit.expand, children: [
          if (look != null)
            RawImage(image: look, fit: BoxFit.fill, filterQuality: FilterQuality.medium)
          else
            Opacity(
              opacity: 0.6,
              child: CustomPaint(painter: _CropPainter(item.image, session.cropOf(item))),
            ),
          if (look == null)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(height: 6),
                Text(l.preparing, style: theme.textTheme.labelMedium),
              ]),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              tooltip: l.removePhoto,
              icon: const Icon(Icons.close, size: 18),
              onPressed: onRemove,
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onTap,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(l.edit),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The crop of a photo, before its frame look is ready.
class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop);

  final ui.Image image;
  final CropRect crop;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
        image,
        Rect.fromLTWH(crop.x, crop.y, crop.w, crop.h),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );

  @override
  bool shouldRepaint(_CropPainter old) => old.image != image || old.crop != crop;
}
