import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/api_error.dart';
import '../../data/frame_link.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/frame_admin.dart';
import '../../state/photos.dart';
import '../../state/providers.dart';
import '../../widgets/side_panel.dart';
import 'invite_sheet.dart';

/// People (app-flow §5.1–5.2): everyone on the frame; the owner invites, removes and
/// revokes invites; anyone else can leave.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key, required this.address});

  final FrameAddress address;

  Future<bool> _confirm(BuildContext context, String text, String action) async {
    final l = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(text),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
            ],
          ),
        ) ??
        false;
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(membersProvider(address));
    ref.invalidate(memberNamesProvider(address));
    ref.invalidate(invitesProvider(address));
    ref.invalidate(usageProvider(address));
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Member m, String frameName) async {
    final l = AppLocalizations.of(context);
    if (!await _confirm(context, l.removePersonConfirm(m.displayName, frameName), l.removePerson)) return;
    try {
      await ref.read(frameApiProvider(address)).removeMember(m.userId);
    } on ApiException {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.somethingWrong)));
    }
    _refresh(ref);
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Member me, String frameName) async {
    final l = AppLocalizations.of(context);
    if (!await _confirm(context, l.leaveFrameConfirm(frameName), l.leave)) return;
    try {
      await ref.read(frameApiProvider(address)).removeMember(me.userId);
    } on ApiException {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.somethingWrong)));
      return;
    }
    if (!context.mounted) return;
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    unawaited(ref.read(frameDirectoryProvider).remove([address]));
    await ref.read(framesProvider.notifier).remove(address);
    // Close the side sheet (or page) first: going Home doesn't remove a sheet.
    if (navigator.canPop()) navigator.pop();
    router.go('/home');
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, Invite invite) async {
    try {
      await ref.read(frameApiProvider(address)).revokeInvite(invite.id);
    } on ApiException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).somethingWrong)));
      }
    }
    ref.invalidate(invitesProvider(address));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = ref.watch(frameViewProvider(address)).value?.summary;
    final members = ref.watch(membersProvider(address));
    final owner = summary?.isMine ?? false;
    final invites = owner ? ref.watch(invitesProvider(address)).value ?? const <Invite>[] : const <Invite>[];
    final frameName = summary?.frame.name ?? l.unknownFrame;
    final date = DateFormat.MMMd(Localizations.localeOf(context).toString());

    return Scaffold(
      appBar: PanelAppBar(title: l.people),
      body: switch (members) {
        AsyncData(value: final list) => RefreshIndicator(
            onRefresh: () async {
              _refresh(ref);
              await ref.read(membersProvider(address).future);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (owner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: FilledButton.icon(
                      onPressed: () => showInviteSheet(context, address, frameName),
                      icon: const Icon(Icons.person_add_alt),
                      label: Text(l.inviteSomeone),
                    ),
                  ),
                for (final m in list)
                  _PersonRow(
                    member: m,
                    isMe: m.userId == summary?.me.userId,
                    onRemove: owner && !m.isOwner ? () => _remove(context, ref, m, frameName) : null,
                  ),
                if (owner && list.length == 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(l.justYou, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                if (invites.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                    child: Text(l.activeInvites, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
                  ),
                  for (final i in invites)
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: Text(i.maxUses == 1
                          ? l.inviteForOne(date.format(i.expiresAt.toLocal()))
                          : l.inviteForMany(i.uses, i.maxUses, date.format(i.expiresAt.toLocal()))),
                      trailing: TextButton(onPressed: () => _revoke(context, ref, i), child: Text(l.revoke)),
                    ),
                ],
                if (summary != null && !owner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      onPressed: () => _leave(context, ref, summary.me, frameName),
                      icon: const Icon(Icons.logout),
                      label: Text(l.leaveFrame),
                    ),
                  ),
              ],
            ),
          ),
        AsyncError() => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(l.somethingWrong),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => _refresh(ref), child: Text(l.tryAgain)),
            ]),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.member, required this.isMe, this.onRemove});

  final Member member;
  final bool isMe;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget badge(String text) => Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
        );
    final name = member.displayName;
    return ListTile(
      leading: CircleAvatar(child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase())),
      title: Row(children: [
        Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        if (member.isOwner) badge(l.ownerBadge),
        if (isMe) badge(l.youBadge),
      ]),
      trailing: onRemove == null ? null : TextButton(onPressed: onRemove, child: Text(l.removePerson)),
    );
  }
}
