import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

enum CheckState { waiting, running, done, failed }

/// One row of a checklist that fills in (setup, connecting the frame). The state is
/// shown by the icon and said by screen readers (app-flow §8.3: never by colour or
/// icon alone).
class ChecklistRow extends StatelessWidget {
  const ChecklistRow({super.key, required this.title, required this.state, this.hint});

  final String title;
  final CheckState state;

  /// Shown under the title while it runs.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final running = state == CheckState.running;
    final icon = switch (state) {
      CheckState.done => Icon(Icons.check_circle, color: scheme.primary),
      CheckState.running => const SizedBox(
          width: 24,
          height: 24,
          child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2.5)),
        ),
      CheckState.failed => Icon(Icons.error, color: scheme.error),
      CheckState.waiting => Icon(Icons.radio_button_unchecked, color: scheme.outline),
    };
    final said = switch (state) {
      CheckState.done => l.stepDone,
      CheckState.running => l.stepRunning,
      CheckState.failed => l.stepFailed,
      CheckState.waiting => l.stepWaiting,
    };
    return Semantics(
      label: '$title, $said',
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: icon,
        title: Text(title, style: TextStyle(fontWeight: running ? FontWeight.w600 : null)),
        subtitle: running && hint != null ? Text(hint!) : null,
      ),
    );
  }
}
