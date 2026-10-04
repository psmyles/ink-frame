import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../data/frame_link.dart';

/// Ctrl/Cmd+V anywhere on the screen pastes an invite link (app-flow §2.3, desktop).
/// A focused text field still handles its own paste.
class PasteLinkShortcut extends StatelessWidget {
  const PasteLinkShortcut({super.key, required this.onLink, required this.child});

  /// Called with the pasted text when it's an Ink Frame link.
  final ValueChanged<String> onLink;
  final Widget child;

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text != null && FrameLink.parse(text) != null) onLink(text);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _paste,
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): _paste,
        },
        child: Focus(autofocus: true, child: child),
      );
}
