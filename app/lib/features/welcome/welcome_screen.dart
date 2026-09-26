import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/frame_mark.dart';

/// First run (app-flow §1.1). Most people are invited, so that's the primary action.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: FrameMark(size: 120)),
                  const SizedBox(height: 28),
                  Text(l.appTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    l.tagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 40),
                  FilledButton(onPressed: () => context.push('/join'), child: Text(l.invited)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => context.push('/setup'), child: Text(l.setUpFrame)),
                  const SizedBox(height: 20),
                  TextButton(onPressed: () => context.push('/join?mode=signin'), child: Text(l.alreadyUse)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
