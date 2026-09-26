import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/frame_link.dart';
import '../../l10n/app_localizations.dart';
import '../../state/photos.dart';

/// Owner, frame set to "In order" (D8): drag to change the order. Each drop is one
/// `POST /images/reorder`.
class ReorderScreen extends ConsumerWidget {
  const ReorderScreen({super.key, required this.address});

  final FrameAddress address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final images = ref.watch(photosProvider(address)).value ?? const [];
    final model = ref.watch(frameModelProvider(address)).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.reorder),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.done))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(l.reorderHint, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: images.length,
              onReorderItem: (from, to) async {
                try {
                  await ref.read(photosProvider(address).notifier).move(from, to);
                } catch (_) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.somethingWrong)));
                }
              },
              itemBuilder: (context, i) {
                final image = images[i];
                return ListTile(
                  key: ValueKey(image.id),
                  leading: SizedBox(
                    width: 80,
                    child: AspectRatio(
                      aspectRatio: model?.aspect ?? 5 / 3,
                      child: Consumer(builder: (context, ref, _) {
                        final bytes = ref.watch(displayBytesProvider((address, image)));
                        return bytes.hasValue ? Image.memory(bytes.value!, fit: BoxFit.cover) : const SizedBox.shrink();
                      }),
                    ),
                  ),
                  title: Text('${i + 1}'),
                  trailing: const Icon(Icons.drag_handle),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
