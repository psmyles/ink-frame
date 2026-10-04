import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/sign_in_service.dart';
import '../data/frame_connection.dart';
import '../l10n/app_localizations.dart';
import '../state/more_frames.dart';
import '../state/providers.dart';

/// "1 more frame is on your account" with Add to this device (app-flow §1.4): frames
/// set up or joined on another device. Nothing when there are none.
class MoreFramesCard extends ConsumerStatefulWidget {
  const MoreFramesCard({super.key});

  @override
  ConsumerState<MoreFramesCard> createState() => _MoreFramesCardState();
}

class _MoreFramesCardState extends ConsumerState<MoreFramesCard> {
  var _busy = false;

  Future<void> _add() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(signInServiceProvider);
    final method = await ref.read(frameDirectoryProvider).provider() == 'apple' ? SignInMethod.apple : SignInMethod.google;
    if (!service.methods(devMode: false).contains(method)) {
      messenger.showSnackBar(SnackBar(content: Text(l.moreAlbumsElsewhere)));
      return;
    }
    setState(() => _busy = true);
    try {
      final fresh = ref.read(lastCredentialProvider.notifier).fresh;
      final credential =
          fresh is IdTokenCredential ? fresh : await (method == SignInMethod.apple ? service.apple() : service.google());
      await ref.read(moreFramesProvider.notifier).add(credential);
    } on SignInCancelled {
      // Stay put.
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.moreAlbumsFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final more = ref.watch(moreFramesProvider).value ?? const [];
    if (more.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.devices_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(l.moreAlbums(more.length), style: theme.textTheme.titleSmall)),
              IconButton(
                tooltip: l.notNow,
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(moreFramesProvider.notifier).hide(),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 36, right: 8),
              child: Text(l.moreAlbumsBody(more.length), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: FilledButton.tonal(
                onPressed: _busy ? null : _add,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(l.addToDevice),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
