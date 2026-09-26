import 'package:flutter/material.dart';

/// A simple picture frame with a landscape in it: the app's mark.
class FrameMark extends StatelessWidget {
  const FrameMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size * 0.78,
        child: CustomPaint(painter: _MarkPainter(scheme.onSurface, scheme.primary, scheme.secondary)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.frame, this.sun, this.hill);

  final Color frame;
  final Color sun;
  final Color hill;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.06;
    final outer = RRect.fromRectAndRadius(
      Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke),
      Radius.circular(size.width * 0.08),
    );
    final inner = outer.deflate(stroke * 1.6);
    canvas.drawRRect(outer, Paint()..color = frame..style = PaintingStyle.stroke..strokeWidth = stroke);
    canvas.save();
    canvas.clipRRect(inner);
    final r = inner.outerRect;
    canvas.drawCircle(Offset(r.left + r.width * 0.72, r.top + r.height * 0.32), r.height * 0.14, Paint()..color = sun);
    final path = Path()
      ..moveTo(r.left, r.bottom)
      ..lineTo(r.left, r.top + r.height * 0.72)
      ..quadraticBezierTo(r.left + r.width * 0.3, r.top + r.height * 0.42, r.left + r.width * 0.55, r.top + r.height * 0.7)
      ..quadraticBezierTo(r.left + r.width * 0.78, r.top + r.height * 0.55, r.right, r.top + r.height * 0.68)
      ..lineTo(r.right, r.bottom)
      ..close();
    canvas.drawPath(path, Paint()..color = hill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.frame != frame || old.sun != sun || old.hill != hill;
}
