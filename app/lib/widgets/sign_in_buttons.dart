import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/sign_in_service.dart';
import '../data/frame_connection.dart';
import '../l10n/app_localizations.dart';
import '../state/providers.dart';

/// Continue with Google / Apple, for what this build and platform offer (app-flow §7.1).
class SignInButtons extends ConsumerWidget {
  const SignInButtons({super.key, required this.methods, required this.onPressed, this.busy = false});

  final List<SignInMethod> methods;
  final void Function(Future<IdTokenCredential> Function() signIn) onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final service = ref.read(signInServiceProvider);
    final apple = !kIsWeb && (Platform.isIOS || Platform.isMacOS) && methods.contains(SignInMethod.apple);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (methods.contains(SignInMethod.google))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => onPressed(service.google),
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(l.continueWithGoogle),
            ),
          ),
        if (apple)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton.icon(
              onPressed: busy ? null : () => onPressed(service.apple),
              icon: const Icon(Icons.apple),
              label: Text(l.continueWithApple),
            ),
          ),
        if (apple && Platform.isIOS)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(l.appleHint, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}
