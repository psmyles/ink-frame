import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/api_error.dart';
import '../features/frame/frame_status.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../theme/theme.dart';

String ago(AppLocalizations l, DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return l.justNow;
  if (d.inHours < 1) return l.minutesAgo(d.inMinutes);
  if (d.inDays < 1) return l.hoursAgo(d.inHours);
  return l.daysAgo(d.inDays);
}

/// "since Tuesday" within a week, else "since 3 Mar".
String since(BuildContext context, DateTime t, DateTime now) {
  final locale = Localizations.localeOf(context).toString();
  final local = t.toLocal();
  return now.difference(t).inDays < 7 ? DateFormat.EEEE(locale).format(local) : DateFormat.MMMd(locale).format(local);
}

/// The frame's one-line status (app-flow §4.2), or a short error state.
class StatusLine extends StatelessWidget {
  const StatusLine(this.view, {super.key, this.now});

  final FrameView view;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ink = context.ink;
    final at = now ?? DateTime.now();
    final summary = view.summary;

    final (IconData icon, Color color, String text) = switch (view.error?.code) {
      ApiException.asleep => (Icons.bedtime_outlined, ink.warning, l.asleepShort),
      ApiException.offline => (Icons.cloud_off_outlined, theme.colorScheme.onSurfaceVariant, l.offline),
      ApiException.notMember => (Icons.block, theme.colorScheme.error, l.removedFromFrame),
      ApiException.signedOut => (Icons.login, ink.warning, l.signedOutOfFrame),
      null => _status(context, l, FrameStatus.of(summary!.frame, at), at),
      _ => (Icons.error_outline, theme.colorScheme.error, l.somethingWrong),
    };

    final battery = summary == null ? null : FrameStatus.of(summary.frame, at).lowBattery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(theme, icon, color, text),
        if (battery != null) ...[
          const SizedBox(height: 4),
          _row(theme, Icons.battery_alert, ink.warning, l.batteryLow(battery)),
        ],
      ],
    );
  }

  Widget _row(ThemeData theme, IconData icon, Color color, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        ],
      );

  (IconData, Color, String) _status(BuildContext context, AppLocalizations l, FrameStatus s, DateTime at) {
    final ink = context.ink;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return switch (s.kind) {
      StatusKind.upToDate => (Icons.check_circle_outline, ink.ok, l.statusUpToDate(ago(l, s.lastSeen!, at))),
      StatusKind.changesWaiting => (
          Icons.schedule,
          muted,
          s.nextCheck == null
              ? l.statusChangesWaitingSoon
              : l.statusChangesWaiting(
                  DateFormat.jm(Localizations.localeOf(context).toString()).format(s.nextCheck!.toLocal())),
        ),
      StatusKind.firstCheck => (Icons.schedule, muted, l.statusFirstCheck),
      StatusKind.notConnected => (Icons.link_off, muted, l.statusNotConnected),
      StatusKind.notCheckedIn => (Icons.warning_amber, ink.warning, l.statusNotCheckedIn(since(context, s.lastSeen!, at))),
    };
  }
}
