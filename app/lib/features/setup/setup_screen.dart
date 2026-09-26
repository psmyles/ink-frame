import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

/// Set up a frame (app-flow §1.3): built in Phase 3e.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.setUpFrame)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.setUpComing, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: () => context.pushReplacement('/join'), child: Text(l.joinWithInvite)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
