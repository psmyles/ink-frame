import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/frame_link.dart';
import '../../imaging/dither.dart' show preview;
import '../../imaging/od_pipeline.dart' show OdSettings;
import '../../imaging/pipeline.dart';
import '../../imaging/resize.dart';
import '../../l10n/app_localizations.dart';
import '../../state/photos.dart';
import 'crop_editor.dart';
import 'source_photo.dart';

/// One photo being prepared.
class _Item {
  _Item(this.source) : image = source.image, rgba = source.rgba, width = source.width, height = source.height;

  final SourcePhoto source;
  ui.Image image;
  Uint8List rgba;
  int width, height;
  CropRect? crop;
  PhotoAdjustments adjustments = const PhotoAdjustments();

  /// Automatic's settings for the current crop (reset when the crop moves).
  OdSettings? auto;
  ui.Image? preview;
  var previewStale = true;
}

/// Prepare (app-flow §3.3): crop, rotate, preview, optional adjustments, upload.
class PrepareScreen extends ConsumerStatefulWidget {
  const PrepareScreen({super.key, required this.address, required this.photos});

  final FrameAddress address;
  final List<SourcePhoto> photos;

  @override
  ConsumerState<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends ConsumerState<PrepareScreen> {
  late final List<_Item> _items = [for (final p in widget.photos) _Item(p)];
  var _current = 0;
  var _onFrame = false;
  var _rendering = false;
  Timer? _debounce;
  var _renderToken = 0;

  _Item get _item => _items[_current];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  CropRect _cropOf(_Item it, double aspect) => it.crop ?? CropRect.center(it.width, it.height, aspect);

  void _changed({bool cropMoved = false}) {
    if (cropMoved) _item.auto = null;
    _item.previewStale = true;
    setState(() {});
    if (_onFrame) _schedulePreview();
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _renderPreview);
  }

  Future<void> _renderPreview() async {
    final model = ref.read(frameModelProvider(widget.address)).value;
    if (model == null || !mounted) return;
    final it = _item;
    if (!it.previewStale && it.preview != null) return;
    final token = ++_renderToken;
    setState(() => _rendering = true);
    final job = _jobFor(it, model);
    final (indices, auto) = await Isolate.run(() => ditherPhoto(job));
    final rgba = preview(indices, model.palette);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, model.model.width, model.model.height, ui.PixelFormat.rgba8888, completer.complete);
    final image = await completer.future;
    if (!mounted || token != _renderToken) return;
    setState(() {
      it
        ..auto = auto ?? it.auto
        ..preview = image
        ..previewStale = false;
      _rendering = false;
    });
  }

  PhotoJob _jobFor(_Item it, FrameModel model) => PhotoJob(
        rgba: it.rgba,
        width: it.width,
        height: it.height,
        outWidth: model.model.width,
        outHeight: model.model.height,
        palette: model.palette,
        crop: _cropOf(it, model.aspect),
        adjustments: it.adjustments,
        autoSettings: it.auto,
      );

  Future<void> _rotate() async {
    final it = _item;
    final (rgba, w, h) = rotate(it.rgba, it.width, it.height, 1);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
    final image = await completer.future;
    setState(() {
      it
        ..rgba = rgba
        ..width = w
        ..height = h
        ..image = image
        ..crop = null;
    });
    _changed(cropMoved: true);
  }

  void _remove(int index) {
    if (_items.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _items.removeAt(index);
      if (_current >= _items.length) _current = _items.length - 1;
    });
    if (_onFrame) _schedulePreview();
  }

  void _upload(FrameModel model) {
    ref.read(uploadQueueProvider(widget.address).notifier).addAll([for (final it in _items) _jobFor(it, model)]);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final model = ref.watch(frameModelProvider(widget.address)).value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: l.cancel, onPressed: () => Navigator.of(context).pop()),
        title: Text(l.prepareTitle(_items.length)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: model == null ? null : () => _upload(model),
              child: Text(l.uploadCount(_items.length)),
            ),
          ),
        ],
      ),
      body: model == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= 900;
              final editor = _editor(l, model);
              final panel = _AdjustPanel(
                value: _item.adjustments,
                onChanged: (a) {
                  _item.adjustments = a;
                  _changed();
                },
                onUseForAll: () {
                  for (final it in _items) {
                    it
                      ..adjustments = _item.adjustments
                      ..previewStale = true;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.appliedToAll)));
                  setState(() {});
                },
              );
              return Column(
                children: [
                  Expanded(
                    child: wide
                        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Padding(padding: const EdgeInsets.all(16), child: editor)),
                            SizedBox(width: 340, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: panel)),
                          ])
                        : ListView(padding: const EdgeInsets.all(16), children: [editor, const SizedBox(height: 8), panel]),
                  ),
                  if (_items.length > 1) _strip(l),
                ],
              );
            }),
    );
  }

  Widget _editor(AppLocalizations l, FrameModel model) {
    final it = _item;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              if (_onFrame && it.preview != null)
                AspectRatio(
                  aspectRatio: model.aspect,
                  child: RawImage(image: it.preview, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                )
              else
                CropEditor(
                  image: it.image,
                  aspect: model.aspect,
                  crop: _cropOf(it, model.aspect),
                  onChanged: (c) {
                    it.crop = c;
                    _changed(cropMoved: true);
                  },
                ),
              if (_onFrame && (_rendering || it.previewStale))
                const Positioned.fill(child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator()))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l.original), icon: const Icon(Icons.crop)),
                  ButtonSegment(value: true, label: Text(l.onTheFrame), icon: const Icon(Icons.photo_outlined)),
                ],
                selected: {_onFrame},
                onSelectionChanged: (s) {
                  setState(() => _onFrame = s.single);
                  if (_onFrame) _renderPreview();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: l.rotate, icon: const Icon(Icons.rotate_right), onPressed: _rotate),
          ],
        ),
      ],
    );
  }

  Widget _strip(AppLocalizations l) => SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => Stack(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => _current = i);
                  if (_onFrame) _renderPreview();
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: i == _current ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: RawImage(image: _items[i].image, width: 96, height: 64, fit: BoxFit.cover),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  iconSize: 14,
                  tooltip: l.removePhoto,
                  icon: const Icon(Icons.close),
                  onPressed: () => _remove(i),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Adjust (collapsed): Automatic, three plain sliders, and More options.
class _AdjustPanel extends StatelessWidget {
  const _AdjustPanel({required this.value, required this.onChanged, required this.onUseForAll});

  final PhotoAdjustments value;
  final ValueChanged<PhotoAdjustments> onChanged;
  final VoidCallback onUseForAll;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget slider(String label, String low, String high, double v, PhotoAdjustments Function(double) set) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(left: 16, top: 8), child: Text(label, style: theme.textTheme.titleSmall)),
            Slider(value: v, min: -1, max: 1, divisions: 20, onChanged: (x) => onChanged(set(x))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text(low, style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(high, style: theme.textTheme.bodySmall),
              ]),
            ),
          ],
        );
    final patterns = {
      DotPattern.fine: l.patternFine,
      DotPattern.smooth: l.patternSmooth,
      DotPattern.crisp: l.patternCrisp,
      DotPattern.grid: l.patternGrid,
      DotPattern.grainy: l.patternGrainy,
    };
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.tune),
        title: Text(l.adjust),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: [
          SwitchListTile(
            title: Text(l.automatic),
            subtitle: Text(l.automaticHint),
            value: value.automatic,
            onChanged: (v) => onChanged(value.copyWith(automatic: v)),
          ),
          slider(l.brightness, l.darker, l.brighter, value.brightness, (x) => value.copyWith(brightness: x)),
          slider(l.contrast, l.softer, l.stronger, value.contrast, (x) => value.copyWith(contrast: x)),
          slider(l.colour, l.muted, l.vivid, value.colour, (x) => value.copyWith(colour: x)),
          ExpansionTile(
            shape: const Border(),
            title: Text(l.moreOptions),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(alignment: Alignment.centerLeft, child: Text(l.dotPattern, style: theme.textTheme.titleSmall)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in patterns.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: value.pattern == e.key,
                      onSelected: (_) => onChanged(value.copyWith(pattern: e.key)),
                    ),
                ]),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: OverflowBar(alignment: MainAxisAlignment.spaceBetween, children: [
              TextButton(onPressed: value.isDefault ? null : () => onChanged(const PhotoAdjustments()), child: Text(l.reset)),
              TextButton(onPressed: onUseForAll, child: Text(l.useForAll)),
            ]),
          ),
        ],
      ),
    );
  }
}
