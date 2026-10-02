import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../imaging/pipeline.dart';
import '../../l10n/app_localizations.dart';
import 'frame_canvas.dart';
import 'prepare_session.dart';

/// One photo, opened from the overview (app-flow §3.3): "Photo 2 of 5", arrows to
/// step through the others, and Done back to the overview.
class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.session, required this.index});

  final PrepareSession session;
  final int index;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  late int _index = widget.index;

  PrepareSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session.setFocus(_session.items[_index]);
  }

  @override
  void dispose() {
    _session.setFocus(null);
    super.dispose();
  }

  void _go(int to) {
    setState(() => _index = to);
    _session.setFocus(_session.items[to]);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final count = _session.items.length;
    return Scaffold(
      appBar: AppBar(
        // Done is the way back; dropping the back arrow leaves room for the title on phones.
        automaticallyImplyLeading: false,
        title: FittedBox(fit: BoxFit.scaleDown, child: Text(l.photoOfCount(_index + 1, count))),
        actions: [
          IconButton(
            tooltip: l.previousPhoto,
            icon: const Icon(Icons.chevron_left),
            onPressed: _index > 0 ? () => _go(_index - 1) : null,
          ),
          IconButton(
            tooltip: l.nextPhoto,
            icon: const Icon(Icons.chevron_right),
            onPressed: _index < count - 1 ? () => _go(_index + 1) : null,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.done),
            ),
          ),
        ],
      ),
      body: PhotoEditor(key: ValueKey(_session.items[_index]), session: _session, item: _session.items[_index]),
    );
  }
}

/// The editor body: the frame-shaped canvas (also the crop), Rotate / Hold to
/// compare / Reset, and Adjust. The canvas never scrolls away: on narrow screens
/// it sits on top with the controls scrolling below it, on wide or landscape
/// screens the controls are a side panel.
class PhotoEditor extends StatefulWidget {
  const PhotoEditor({super.key, required this.session, required this.item});

  final PrepareSession session;
  final PrepItem item;

  @override
  State<PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<PhotoEditor> {
  var _compare = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = widget.session, it = widget.item;
    final touch = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };

    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final canvas = FrameCanvas(
          image: it.image,
          aspect: s.model.aspect,
          crop: s.cropOf(it),
          onChanged: (c) => s.setCrop(it, c),
          preview: it.preview,
          updating: it.updating,
          showOriginal: _compare,
          originalLabel: l.original,
          preparingLabel: l.preparing,
          updatingLabel: l.updating,
        );
        final hint = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            touch ? l.moveHintTouch : l.moveHintMouse,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        );
        final tools = Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => s.rotate(it),
                      icon: const Icon(Icons.rotate_right),
                      label: Text(l.rotate, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HoldButton(
                      label: l.viewOriginal,
                      tooltip: l.viewOriginalHint,
                      onHold: (v) => setState(() => _compare = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final adjust = AdjustControls(
          value: it.adjustments,
          onChanged: (a) => s.setAdjustments(it, a),
          onStartOver: it.isOriginal ? null : () => s.reset(it),
          onUseForAll: s.items.length > 1
              ? () {
                  s.useForAll(it.adjustments);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.appliedToAll)));
                }
              : null,
        );

        return LayoutBuilder(
          builder: (context, box) {
            final side = box.maxWidth >= 720 && box.maxWidth > box.maxHeight * 1.1;
            if (side) {
              // Keep the hint and buttons under the photo when there's room, else in the panel.
              final under = box.maxHeight >= 560;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: under
                        ? Column(
                            children: [
                              Expanded(child: canvas),
                              hint,
                              tools,
                              const SizedBox(height: 12),
                            ],
                          )
                        : canvas,
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: math.min(380, box.maxWidth * 0.42),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      children: [
                        if (!under) ...[hint, tools, const Divider(height: 24)],
                        adjust,
                      ],
                    ),
                  ),
                ],
              );
            }
            final canvasHeight = math.min(
              (box.maxWidth - FrameCanvas.margin.horizontal) / s.model.aspect + FrameCanvas.margin.vertical,
              box.maxHeight * 0.5,
            );
            return Column(
              children: [
                SizedBox(height: canvasHeight, child: canvas),
                hint,
                tools,
                const Divider(height: 1),
                Expanded(
                  child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [adjust]),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Shows the original while pressed (mouse or touch).
class _HoldButton extends StatelessWidget {
  const _HoldButton({required this.label, required this.tooltip, required this.onHold});

  final String label, tooltip;
  final ValueChanged<bool> onHold;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 600),
    child: Listener(
      onPointerDown: (_) => onHold(true),
      onPointerUp: (_) => onHold(false),
      onPointerCancel: (_) => onHold(false),
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.compare),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ),
  );
}

/// Automatic, three plain sliders, the dot pattern behind More options, then
/// Use for all / Start over.
/// No technical words (app-flow §3.3).
class AdjustControls extends StatelessWidget {
  const AdjustControls({super.key, required this.value, required this.onChanged, this.onUseForAll, this.onStartOver});

  final PhotoAdjustments value;
  final ValueChanged<PhotoAdjustments> onChanged;

  /// Undo the crop, rotation and adjustments; null when there's nothing to undo.
  final VoidCallback? onStartOver;

  /// Null with a single photo.
  final VoidCallback? onUseForAll;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget slider(String label, double v, PhotoAdjustments Function(double) set) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(label, style: theme.textTheme.titleSmall),
          ),
          Slider(value: v, min: -1, max: 1, divisions: 20, onChanged: (x) => onChanged(set(x))),
        ],
      ),
    );
    final line = Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
    final patterns = {
      DotPattern.fine: l.patternFine,
      DotPattern.smooth: l.patternSmooth,
      DotPattern.crisp: l.patternCrisp,
      DotPattern.grid: l.patternGrid,
      DotPattern.grainy: l.patternGrainy,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          title: Text(l.automatic),
          subtitle: Text(l.automaticHint),
          value: value.automatic,
          onChanged: (v) => onChanged(value.copyWith(automatic: v)),
        ),
        line,
        slider(l.brightness, value.brightness, (x) => value.copyWith(brightness: x)),
        line,
        slider(l.contrast, value.contrast, (x) => value.copyWith(contrast: x)),
        line,
        slider(l.colour, value.colour, (x) => value.copyWith(colour: x)),
        line,
        ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(l.moreOptions),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.dotPattern, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in patterns.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: value.pattern == e.key,
                    onSelected: (_) => onChanged(value.copyWith(pattern: e.key)),
                  ),
              ],
            ),
          ],
        ),
        line,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              if (onUseForAll != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onUseForAll,
                    icon: const Icon(Icons.done_all),
                    label: Text(l.useForAll, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onStartOver,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(l.startOver, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
