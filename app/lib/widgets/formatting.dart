import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// "312 MB", "1 GB", "1.4 GB" (binary units, as Supabase counts storage).
String formatBytes(int bytes, Locale locale) {
  const kb = 1024, mb = kb * 1024, gb = mb * 1024;
  final f = NumberFormat.decimalPatternDigits(locale: locale.toString(), decimalDigits: 1);
  if (bytes >= gb) return '${_trim(f.format(bytes / gb))} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / kb).ceil()} KB';
}

String _trim(String s) => s.replaceFirst(RegExp(r'[.,]0$'), '');

/// "4 hours", "1 day", "2 days".
String formatInterval(AppLocalizations l, int seconds) =>
    seconds % 86400 == 0 ? l.daysCount(seconds ~/ 86400) : l.hoursCount((seconds / 3600).round());

/// `22:00` → the person's clock format.
String formatHhmm(BuildContext context, String hhmm) {
  final t = parseHhmm(hhmm);
  return MaterialLocalizations.of(context)
      .formatTimeOfDay(t, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
}

TimeOfDay parseHhmm(String hhmm) => TimeOfDay(hour: int.parse(hhmm.substring(0, 2)), minute: int.parse(hhmm.substring(3, 5)));

String toHhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `America/New_York` → ("New York", "America").
(String, String) timeZoneParts(String zone) {
  final i = zone.lastIndexOf('/');
  if (i < 0) return (zone, '');
  return (zone.substring(i + 1).replaceAll('_', ' '), zone.substring(0, i).replaceAll('_', ' '));
}
