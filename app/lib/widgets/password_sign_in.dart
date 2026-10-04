import 'package:flutter/material.dart';

import '../data/frame_connection.dart';
import '../l10n/app_localizations.dart';

/// Email and password: developer mode, dev projects only (app-flow §7.1).
class PasswordSignIn extends StatefulWidget {
  const PasswordSignIn({super.key, required this.onSignIn, this.busy = false});

  final void Function(PasswordCredential credential) onSignIn;
  final bool busy;

  @override
  State<PasswordSignIn> createState() => _PasswordSignInState();
}

class _PasswordSignInState extends State<PasswordSignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _email.text.trim(), password = _password.text;
    if (email.isEmpty || password.length < 6) return;
    widget.onSignIn(PasswordCredential(email, password));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(l.devSignIn, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(labelText: l.email),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(labelText: l.password),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: widget.busy ? null : _submit, child: Text(l.signIn)),
      ],
    );
  }
}
