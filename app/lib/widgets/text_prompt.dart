import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Asks for a short piece of text (a name). Returns it trimmed, or null if cancelled
/// or left empty or unchanged.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String initial,
  String? label,
  String? hint,
  int maxLength = 40,
}) async {
  final v = await showDialog<String>(
    context: context,
    builder: (_) => _TextPrompt(title: title, initial: initial, label: label, hint: hint, maxLength: maxLength),
  );
  final t = v?.trim() ?? '';
  return t.isEmpty || t == initial ? null : t;
}

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({required this.title, required this.initial, this.label, this.hint, required this.maxLength});

  final String title, initial;
  final String? label, hint;
  final int maxLength;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  // Owned here so it outlives the dialog's closing animation.
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.hint != null) ...[Text(widget.hint!), const SizedBox(height: 8)],
        TextField(
          controller: _field,
          autofocus: true,
          maxLength: widget.maxLength,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _field.text), child: Text(l.save)),
      ],
    );
  }
}
