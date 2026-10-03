import 'dart:async';

import 'package:flutter/material.dart';

/// Shows [child] only once a wait has lasted [delay], so a quick load doesn't
/// flash a spinner, and a slow one never looks frozen.
class AfterDelay extends StatefulWidget {
  const AfterDelay({super.key, required this.child, this.delay = const Duration(milliseconds: 300)});

  final Widget child;
  final Duration delay;

  @override
  State<AfterDelay> createState() => _AfterDelayState();
}

class _AfterDelayState extends State<AfterDelay> {
  late final Timer _timer;
  var _shown = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () => setState(() => _shown = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _shown ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: widget.child,
      );
}

/// A small spinner with a line of text, e.g. "Loading your frames…".
class LoadingLine extends StatelessWidget {
  const LoadingLine(this.text, {super.key, this.size = 18});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 12),
        Flexible(child: Text(text, style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
      ],
    );
  }
}
