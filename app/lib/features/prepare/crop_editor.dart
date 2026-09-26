import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../imaging/resize.dart';

/// Crop locked to the frame's aspect (app-flow §3.3): drag to move, pinch or scroll
/// to zoom. What's inside the box is exactly what the frame gets.
class CropEditor extends StatefulWidget {
  const CropEditor({super.key, required this.image, required this.aspect, required this.crop, required this.onChanged});

  final ui.Image image;
  final double aspect;
  final CropRect crop;
  final ValueChanged<CropRect> onChanged;

  @override
  State<CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<CropEditor> {
  late CropRect _start;
  double _viewW = 1;

  int get _imgW => widget.image.width;
  int get _imgH => widget.image.height;

  /// Keeps the aspect, a sensible minimum size, and the box inside the image.
  CropRect _clamp(double cx, double cy, double w) {
    final maxW = math.min(_imgW.toDouble(), _imgH * widget.aspect);
    final minW = math.min(maxW, math.max(64.0, maxW / 8));
    w = w.clamp(minW, maxW);
    final h = w / widget.aspect;
    final x = (cx - w / 2).clamp(0.0, _imgW - w);
    final y = (cy - h / 2).clamp(0.0, _imgH - h);
    return CropRect(x, y, w, h);
  }

  void _zoom(double factor, Offset focal) {
    final c = widget.crop;
    // Keep the image point under the focal point in place.
    final fx = c.x + focal.dx / _viewW * c.w, fy = c.y + focal.dy / _viewW * c.w;
    final w = c.w / factor;
    final nx = fx - (focal.dx / _viewW) * w, ny = fy - (focal.dy / _viewW) * w;
    widget.onChanged(_clamp(nx + w / 2, ny + w / widget.aspect / 2, w));
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspect,
      child: LayoutBuilder(builder: (context, box) {
        _viewW = box.maxWidth;
        return Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) _zoom(e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1, e.localPosition);
          },
          child: GestureDetector(
            onScaleStart: (_) => _start = widget.crop,
            onScaleUpdate: (d) {
              final s = _start;
              final pxPerView = s.w / _viewW; // image pixels per screen pixel
              final w = s.w / d.scale;
              final cx = s.x + s.w / 2 - d.focalPointDelta.dx * pxPerView;
              final cy = s.y + s.h / 2 - d.focalPointDelta.dy * pxPerView;
              final next = _clamp(cx, cy, w);
              _start = CropRect(next.x, next.y, s.w, s.h); // accumulate the pan
              widget.onChanged(next);
            },
            child: CustomPaint(
              painter: _CropPainter(widget.image, widget.crop),
              size: Size.infinite,
            ),
          ),
        );
      }),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.crop);

  final ui.Image image;
  final CropRect crop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(crop.x, crop.y, crop.w, crop.h),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.image != image || old.crop != crop;
}
