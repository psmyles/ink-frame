import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../imaging/resize.dart';

/// The frame-shaped window that is also the crop (app-flow §3.3): drag to move
/// the photo, pinch or scroll to zoom. At rest it shows [preview], the frame
/// look; while moving it shows the photo itself. The parts that will be cut off
/// always show dimmed around the window, so it's clear there's more photo there.
class FrameCanvas extends StatefulWidget {
  const FrameCanvas({
    super.key,
    required this.image,
    required this.aspect,
    required this.crop,
    required this.onChanged,
    this.preview,
    this.updating = false,
    this.showOriginal = false,
    this.originalLabel,
    this.preparingLabel,
    this.updatingLabel,
  });

  final ui.Image image;
  final double aspect;
  final CropRect crop;
  final ValueChanged<CropRect> onChanged;

  /// The frame look for the current crop; null while preparing.
  final ui.Image? preview;

  /// [preview] is behind a slider change and a newer one is on its way.
  final bool updating;

  /// Held "compare": show the photo, not the frame look.
  final bool showOriginal;
  final String? originalLabel, preparingLabel, updatingLabel;

  /// Space around the window where the cut-off parts show.
  static const margin = EdgeInsets.symmetric(horizontal: 12, vertical: 28);

  @override
  State<FrameCanvas> createState() => _FrameCanvasState();
}

class _FrameCanvasState extends State<FrameCanvas> {
  late CropRect _current; // the crop during a gesture, ahead of the next rebuild
  double _lastScale = 1;
  var _moving = false;
  Rect _window = Rect.zero;
  Timer? _settle;

  int get _imgW => widget.image.width;
  int get _imgH => widget.image.height;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  void _setMoving(bool v) {
    _settle?.cancel();
    if (v) {
      if (!_moving) setState(() => _moving = true);
    } else {
      // A short pause so the cut-off parts don't flash away mid-gesture.
      _settle = Timer(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _moving = false);
      });
    }
  }

  /// Keeps the aspect, a sensible zoom limit, and the window inside the photo.
  CropRect _clamp(double cx, double cy, double w) {
    final maxW = math.min(_imgW.toDouble(), _imgH * widget.aspect);
    final minW = math.min(maxW, math.max(64.0, maxW / 8));
    w = w.clamp(minW, maxW);
    final h = w / widget.aspect;
    final x = (cx - w / 2).clamp(0.0, _imgW - w);
    final y = (cy - h / 2).clamp(0.0, _imgH - h);
    return CropRect(x, y, w, h);
  }

  /// [from] zoomed by [factor], keeping the photo point under [focal] (canvas coordinates) in place.
  CropRect _zoom(CropRect from, double factor, Offset focal) {
    final s = _window.width / from.w;
    final fx = from.x + (focal.dx - _window.left) / s, fy = from.y + (focal.dy - _window.top) / s;
    final w = from.w / factor, sNew = _window.width / w;
    final nx = fx - (focal.dx - _window.left) / sNew, ny = fy - (focal.dy - _window.top) / sNew;
    return _clamp(nx + w / 2, ny + w / widget.aspect / 2, w);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final inner = FrameCanvas.margin.deflateRect(Offset.zero & box.biggest);
      final w = math.min(inner.width, inner.height * widget.aspect);
      _window = Rect.fromCenter(center: inner.center, width: w, height: w / widget.aspect);
      final showPhoto = _moving || widget.showOriginal || widget.preview == null;
      final label = widget.showOriginal
          ? widget.originalLabel
          : _moving
              ? null
              : widget.preview == null
                  ? widget.preparingLabel
                  : widget.updating
                      ? widget.updatingLabel
                      : null;

      return MouseRegion(
        cursor: _moving ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _setMoving(true);
              widget.onChanged(_zoom(widget.crop, e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1, e.localPosition));
              _setMoving(false);
            }
          },
          child: GestureDetector(
            onScaleStart: (_) {
              _current = widget.crop;
              _lastScale = 1;
              _setMoving(true);
            },
            onScaleUpdate: (d) {
              // Pan by the focal point's movement, then zoom by the change in scale since the last event.
              final c = _current;
              final pan = d.focalPointDelta / (_window.width / c.w);
              var next = _clamp(c.x + c.w / 2 - pan.dx, c.y + c.h / 2 - pan.dy, c.w);
              if (d.scale != _lastScale) next = _zoom(next, d.scale / _lastScale, d.localFocalPoint);
              _lastScale = d.scale;
              _current = next;
              widget.onChanged(next);
            },
            onScaleEnd: (_) => _setMoving(false),
            onDoubleTap: () => widget.onChanged(CropRect.center(_imgW, _imgH, widget.aspect)),
            child: Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CanvasPainter(
                    image: widget.image,
                    preview: showPhoto ? null : widget.preview,
                    crop: widget.crop,
                    window: _window,
                    dim: theme.colorScheme.surface.withValues(alpha: 0.72),
                    outline: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              if (label != null)
                Positioned(
                  left: _window.left + 8,
                  top: _window.top + 8,
                  child: _Pill(label: label),
                ),
            ]),
          ),
        ),
      );
    });
  }

}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(label, style: theme.textTheme.labelMedium),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.image,
    required this.preview,
    required this.crop,
    required this.window,
    required this.dim,
    required this.outline,
  });

  final ui.Image image;
  final ui.Image? preview;
  final CropRect crop;
  final Rect window;
  final Color dim, outline;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    // The whole photo, placed so the crop lands on the window, dimmed outside it.
    final s = window.width / crop.w;
    final dst = Rect.fromLTWH(window.left - crop.x * s, window.top - crop.y * s, image.width * s, image.height * s);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), dst, paint);
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(bounds), Path()..addRect(window)),
      Paint()..color = dim,
    );
    if (preview case final p?) {
      canvas.drawImageRect(p, Rect.fromLTWH(0, 0, p.width.toDouble(), p.height.toDouble()), window, paint);
    }
    canvas.drawRect(window, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = outline);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.image != image ||
      old.preview != preview ||
      old.crop != crop ||
      old.window != window ||
      old.dim != dim ||
      old.outline != outline;
}
