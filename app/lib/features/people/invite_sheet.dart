import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api_error.dart';
import '../../data/frame_link.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/frame_admin.dart';
import '../../widgets/adaptive_shell.dart';

/// Invite someone (app-flow §5.1): a bottom sheet on phones, a dialog on wide
/// windows. An invite (1 person, 7 days) is made as soon as it opens.
Future<void> showInviteSheet(BuildContext context, FrameAddress address, String frameName) async {
  final container = ProviderScope.containerOf(context);
  final sheet = InviteSheet(address: address, frameName: frameName);
  if (AdaptiveShell.isWide(context)) {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: sheet),
      ),
    );
  } else {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => sheet);
  }
  // The list on People now includes the new invite.
  container.invalidate(invitesProvider(address));
}

/// QR code, Share / Copy link / Copy code, and options for how many people and how
/// long. Changing an option makes a new invite and revokes the one shown before.
class InviteSheet extends ConsumerStatefulWidget {
  const InviteSheet({super.key, required this.address, required this.frameName});

  final FrameAddress address;
  final String frameName;

  @override
  ConsumerState<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<InviteSheet> {
  var _maxUses = 1;
  var _days = 7;
  NewInvite? _invite;
  var _failed = false;
  var _making = 0; // ignores results of superseded requests

  @override
  void initState() {
    super.initState();
    _make();
  }

  Future<void> _make() async {
    final token = ++_making;
    final previous = _invite;
    setState(() {
      _invite = null;
      _failed = false;
    });
    final api = ref.read(frameApiProvider(widget.address));
    try {
      final invite = await api.createInvite(maxUses: _maxUses, expiresIn: Duration(days: _days));
      if (previous != null) {
        try {
          await api.revokeInvite(previous.id);
        } on ApiException {
          // Already used or gone; it lapses on its own.
        }
      }
      if (mounted && token == _making) setState(() => _invite = invite);
    } on ApiException {
      if (mounted && token == _making) setState(() => _failed = true);
    }
  }

  String get _link => FrameLink([widget.address], _invite!.code).toHttps();

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).copied)));
  }

  Future<void> _share(BuildContext buttonContext) async {
    final l = AppLocalizations.of(context);
    final box = buttonContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: l.inviteShareText(widget.frameName, _link),
      subject: l.inviteTitle,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final invite = _invite;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.inviteTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(l.inviteExplain, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: invite != null
                  ? QrImageView(data: _link, backgroundColor: Colors.white, padding: const EdgeInsets.all(12), semanticsLabel: l.inviteTitle)
                  : _failed
                      ? Center(child: OutlinedButton(onPressed: _make, child: Text(l.tryAgain)))
                      : Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(l.makingInvite),
                          ]),
                        ),
            ),
          ),
          const SizedBox(height: 12),
          if (invite != null) ...[
            Text(l.inviteCode, textAlign: TextAlign.center, style: theme.textTheme.labelMedium),
            SelectableText(
              invite.code,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 2, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                onPressed: () => _share(buttonContext),
                icon: const Icon(Icons.share),
                label: Text(l.shareLink),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(onPressed: () => _copy(_link), icon: const Icon(Icons.link), label: Text(l.copyLink)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(invite.code),
                  icon: const Icon(Icons.content_copy),
                  label: Text(l.copyCode),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(l.inviteOptions),
            subtitle: Text('${_maxUses == 1 ? l.onePerson : l.upToTen} · ${l.daysCount(_days)}'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.worksFor, style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 1, label: Text(l.onePerson)),
                  ButtonSegment(value: 10, label: Text(l.upToTen)),
                ],
                selected: {_maxUses},
                showSelectedIcon: false,
                onSelectionChanged: (v) {
                  setState(() => _maxUses = v.single);
                  _make();
                },
              ),
              const SizedBox(height: 12),
              Text(l.expiresIn, style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [for (final d in const [1, 7, 30]) ButtonSegment(value: d, label: Text(l.daysCount(d)))],
                selected: {_days},
                showSelectedIcon: false,
                onSelectionChanged: (v) {
                  setState(() => _days = v.single);
                  _make();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
  }
}
