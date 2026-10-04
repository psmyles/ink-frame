import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/frame_link.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';

/// Which album photos shared from another app go to, when there are several.
/// Returns the chosen album, or null.
Future<FrameAddress?> chooseAlbumFor(BuildContext context, List<FrameAddress> albums) =>
    showDialog<FrameAddress>(context: context, builder: (_) => _ChooseAlbumDialog(albums));

class _ChooseAlbumDialog extends ConsumerWidget {
  const _ChooseAlbumDialog(this.albums);

  final List<FrameAddress> albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.addSharedTo),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final a in albums)
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(ref.watch(cachedFrameProvider(a)).value?.name ?? l.unknownAlbum),
              onTap: () => Navigator.pop(context, a),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel))],
    );
  }
}
