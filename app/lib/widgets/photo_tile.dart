import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/api_error.dart';
import '../data/frame_link.dart';
import '../data/models.dart';
import '../imaging/dither.dart' show preview;
import '../l10n/app_localizations.dart';
import '../state/photos.dart';
import '../state/providers.dart';

/// A photo in the grid, in the panel's calibrated colours (app-flow §3.1).
class PhotoTile extends ConsumerWidget {
  const PhotoTile({super.key, required this.address, required this.image, this.selected = false, this.onTap, this.onLongPress});

  final FrameAddress address;
  final FrameImage image;
  final bool selected;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bytes = ref.watch(displayBytesProvider((address, image)));
    final names = ref.watch(memberNamesProvider(address)).value ?? const {};
    final me = ref.watch(frameViewProvider(address)).value?.summary?.me.userId;
    final who = image.uploadedBy == null
        ? l.someoneWhoLeft
        : (image.uploadedBy == me ? l.you : names[image.uploadedBy] ?? '…');
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(image.createdAt.toLocal());

    return Semantics(
      label: l.photoLabel(who, date),
      selected: selected,
      button: true,
      child: Tooltip(
        message: l.addedBy(who, date),
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHigh,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(fit: StackFit.expand, children: [
              switch (bytes) {
                AsyncData(:final value) => Image.memory(value, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                AsyncError() => Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
                _ => const SizedBox.shrink(),
              },
              if (image.uploadedBy != null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.85),
                    child: Text(who.isEmpty ? '?' : who.characters.first.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              if (selected) ...[
                ColoredBox(color: theme.colorScheme.primary.withValues(alpha: 0.25)),
                Positioned(left: 6, top: 6, child: Icon(Icons.check_circle, color: theme.colorScheme.primary)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A photo still being processed or uploaded, or one that failed (app-flow §3.4–3.5).
class UploadTile extends ConsumerStatefulWidget {
  const UploadTile({super.key, required this.address, required this.item, required this.model});

  final FrameAddress address;
  final UploadItem item;
  final FrameModel model;

  @override
  ConsumerState<UploadTile> createState() => _UploadTileState();
}

class _UploadTileState extends ConsumerState<UploadTile> {
  ui.Image? _preview;
  Uint8List? _for;

  @override
  void didUpdateWidget(UploadTile old) {
    super.didUpdateWidget(old);
    _maybeDecode();
  }

  @override
  void initState() {
    super.initState();
    _maybeDecode();
  }

  void _maybeDecode() {
    final indices = widget.item.preview;
    if (indices == null || identical(indices, _for)) return;
    _for = indices;
    final m = widget.model;
    ui.decodeImageFromPixels(preview(indices, m.palette), m.model.width, m.model.height, ui.PixelFormat.rgba8888, (img) {
      if (mounted) setState(() => _preview = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final item = widget.item;
    final queue = ref.read(uploadQueueProvider(widget.address).notifier);
    final failed = item.status == UploadStatus.failed;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
        if (_preview != null) Opacity(opacity: 0.5, child: RawImage(image: _preview, fit: BoxFit.cover)),
        Center(
          child: failed
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _reason(l, item.error),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, children: [
                      FilledButton.tonal(onPressed: () => queue.retry(item.id), child: Text(l.retry)),
                      IconButton(tooltip: l.removePhoto, onPressed: () => queue.remove(item.id), icon: const Icon(Icons.close)),
                    ]),
                  ]),
                )
              // Words only: a photo is one small file, so there's no progress worth showing.
              : Text(
                  switch (item.status) {
                    UploadStatus.processing => l.preparing,
                    UploadStatus.uploading => l.uploading,
                    _ => l.waiting,
                  },
                  style: theme.textTheme.bodySmall,
                ),
        ),
      ]),
    );
  }
}

/// Why an upload failed, in words for people: the server's own message for known
/// problems (e.g. storage full), a plain one for anything unexpected.
String _reason(AppLocalizations l, ApiException? e) =>
    e == null || e.code == 'unknown' || e.code.startsWith('http_') ? l.uploadFailed : e.message;
