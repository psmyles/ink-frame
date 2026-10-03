import 'package:flutter/material.dart';

import 'adaptive_shell.dart';

/// Opens [builder]'s screen the way app-flow §2.3 wants: pushed full screen in the
/// phone layout, as a side sheet from the right in the two-pane layout.
Future<T?> openPanel<T>(BuildContext context, WidgetBuilder builder) {
  if (MediaQuery.sizeOf(context).width < AdaptiveShell.breakpoint) {
    return Navigator.of(context).push<T>(MaterialPageRoute(builder: builder));
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 8,
        child: SizedBox(
          width: 440,
          height: double.infinity,
          child: _InPanel(child: Builder(builder: builder)),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Whether this screen is showing in a side sheet (its app bar shows ✕, not ←).
bool inPanel(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_InPanel>() != null;

class _InPanel extends InheritedWidget {
  const _InPanel({required super.child});

  @override
  bool updateShouldNotify(_InPanel old) => false;
}

/// The app bar for a screen opened with [openPanel].
class PanelAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PanelAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
        leading: inPanel(context) ? const CloseButton() : null,
        title: Text(title),
        actions: actions,
      );
}
