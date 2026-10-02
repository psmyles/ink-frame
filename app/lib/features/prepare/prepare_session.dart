import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../imaging/auto.dart' show autoSettings, faithful;
import '../../imaging/dither.dart' show preview;
import '../../imaging/od_pipeline.dart' show OdSettings;
import '../../imaging/palette.dart';
import '../../imaging/pipeline.dart';
import '../../imaging/resize.dart';
import '../../state/photos.dart';
import 'source_photo.dart';

/// Automatic's search for one photo, which can be stopped part-way.
class Tuning {
  Tuning(this.result, this.cancel);

  final Future<OdSettings> result;
  final void Function() cancel;
}

/// The off-screen work behind Prepare's previews (overridable for tests).
class PreviewEngine {
  const PreviewEngine({required this.render, required this.tune});

  /// The frame look for a job; quick (~50 ms on a desktop) because the job
  /// already carries Automatic's settings when Automatic is on.
  final Future<ui.Image> Function(PhotoJob job, Palette palette) render;

  /// Automatic's search for the job's crop (~1 s on a desktop, more on phones).
  final Tuning Function(PhotoJob job) tune;
}

final previewEngineProvider = Provider<PreviewEngine>(
  (ref) => const PreviewEngine(render: renderInIsolate, tune: tuneInIsolate),
);

Future<ui.Image> renderInIsolate(PhotoJob job, Palette palette) async {
  final (indices, _) = await Isolate.run(() => ditherPhoto(job));
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(preview(indices, palette), job.outWidth, job.outHeight, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}

/// Runs the search in its own isolate, so a newer crop can kill it outright
/// instead of waiting for a result nobody wants.
Tuning tuneInIsolate(PhotoJob job) {
  final port = ReceivePort();
  final completer = Completer<OdSettings>();
  Isolate? isolate;
  var cancelled = false;
  port.listen((msg) {
    port.close();
    if (completer.isCompleted) return;
    if (msg is OdSettings) {
      completer.complete(msg);
    } else {
      completer.completeError(StateError('tuning failed: $msg'));
    }
  });
  Isolate.spawn(_tune, (port.sendPort, job), onError: port.sendPort, onExit: port.sendPort).then((i) {
    isolate = i;
    if (cancelled) i.kill(priority: Isolate.immediate);
  }, onError: (Object e) {
    port.close();
    if (!completer.isCompleted) completer.completeError(e);
  });
  return Tuning(completer.future, () {
    cancelled = true;
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  });
}

void _tune((SendPort, PhotoJob) args) {
  final (port, job) = args;
  Isolate.exit(port, autoSettings(frameSized(job), job.outWidth, job.outHeight, job.palette));
}

/// One photo being prepared: its (possibly rotated) pixels, crop and adjustments.
class PrepItem {
  PrepItem(this.source) : image = source.image, rgba = source.rgba, width = source.width, height = source.height;

  final SourcePhoto source;
  ui.Image image;
  Uint8List rgba;
  int width, height;
  CropRect? crop;
  PhotoAdjustments adjustments = const PhotoAdjustments();

  /// Automatic's settings for the current crop; null until its search finishes.
  OdSettings? auto;

  /// The last settings Automatic found (for any crop): the first guess for a new one.
  OdSettings? _guess;

  var _version = 0, _cropVersion = 0, _tuneFailedCrop = -1;

  /// Quiet-time timers: work waits until they've run out after the last change.
  Timer? _renderSettle, _tuneSettle;
  bool get _settledForRender => !(_renderSettle?.isActive ?? false);
  bool get _settledForTune => !(_tuneSettle?.isActive ?? false);

  ui.Image? _preview;
  var _previewVersion = -1, _previewCrop = -1;
  OdSettings? _previewSettings;

  /// What the quick preview uses for Automatic: the real settings once found,
  /// meanwhile the last ones found, or the untuned baseline.
  OdSettings? get _settings => adjustments.automatic ? (auto ?? _guess ?? faithful) : null;

  bool get _needsRender => _previewVersion != _version || !identical(_previewSettings, _settings);

  bool get _needsTuning => adjustments.automatic && auto == null && _tuneFailedCrop != _cropVersion;

  /// The newest frame look for the current crop, even if a slider has moved since
  /// (better than flashing back to the photo); null after the crop moves.
  ui.Image? get preview => _previewCrop == _cropVersion ? _preview : null;

  /// [preview] is behind the latest change.
  bool get updating => _needsRender;

  /// As picked: no rotation, centre crop, default adjustments.
  bool get isOriginal => crop == null && identical(image, source.image) && adjustments.isDefault;
}

/// The photos in one Prepare session, and the work that keeps their previews
/// current without making anyone wait (PLAN.md §8.3 has the timings):
/// - a quick lane renders the frame look shortly after any change, using
///   Automatic's last settings while its search runs;
/// - a slow lane runs Automatic's search once a crop has been still for a moment,
///   then the quick lane swaps in the tuned look. Moving the crop again stops a
///   search that's under way.
/// The photo open in the editor goes first in both lanes.
class PrepareSession extends ChangeNotifier {
  PrepareSession(this.model, List<SourcePhoto> photos, this._engine) : items = [for (final p in photos) PrepItem(p)] {
    _pump();
  }

  /// Quiet time before rendering after a slider change, and after a crop change.
  static const settleAdjust = Duration(milliseconds: 80);
  static const settleCrop = Duration(milliseconds: 150);

  /// Quiet time after a crop change before starting Automatic's search.
  static const settleTune = Duration(milliseconds: 500);

  final FrameModel model;
  final List<PrepItem> items;
  final PreviewEngine _engine;

  /// The photo open in the editor.
  PrepItem? focus;

  var _rendering = false, _disposed = false;
  (PrepItem, Tuning)? _tuning;

  CropRect cropOf(PrepItem it) => it.crop ?? CropRect.center(it.width, it.height, model.aspect);

  /// What Upload sends: Automatic's settings only when they were found for this
  /// crop (otherwise the upload queue runs the search itself).
  PhotoJob jobFor(PrepItem it) => _job(it, it.auto);

  PhotoJob _job(PrepItem it, OdSettings? auto) => PhotoJob(
        rgba: it.rgba,
        width: it.width,
        height: it.height,
        outWidth: model.model.width,
        outHeight: model.model.height,
        palette: model.palette,
        crop: cropOf(it),
        adjustments: it.adjustments,
        autoSettings: auto,
      );

  void setCrop(PrepItem it, CropRect crop) {
    it.crop = crop;
    _changed(it, cropMoved: true);
  }

  void setAdjustments(PrepItem it, PhotoAdjustments a) {
    it.adjustments = a;
    _changed(it);
  }

  void useForAll(PhotoAdjustments a) {
    for (final it in items) {
      if (it.adjustments != a) setAdjustments(it, a);
    }
  }

  Future<void> rotate(PrepItem it) async {
    final (rgba, w, h) = _rotate90(it.rgba, it.width, it.height);
    final image = await _decode(rgba, w, h);
    it
      ..rgba = rgba
      ..width = w
      ..height = h
      ..image = image
      ..crop = null;
    _changed(it, cropMoved: true);
  }

  /// Back to the photo as picked: no rotation, centre crop, Automatic.
  void reset(PrepItem it) {
    it
      ..rgba = it.source.rgba
      ..width = it.source.width
      ..height = it.source.height
      ..image = it.source.image
      ..crop = null
      ..adjustments = const PhotoAdjustments();
    _changed(it, cropMoved: true);
  }

  void add(List<SourcePhoto> photos) {
    items.addAll([for (final p in photos) PrepItem(p)]);
    notifyListeners();
    _pump();
  }

  void remove(PrepItem it) {
    items.remove(it);
    it._renderSettle?.cancel();
    it._tuneSettle?.cancel();
    if (focus == it) focus = null;
    if (_tuning?.$1 == it) _stopTuning();
    notifyListeners();
    _pump();
  }

  void setFocus(PrepItem? it) {
    focus = it;
    // Searching another photo while this one waits? This one goes first.
    if (it != null && it._needsTuning && _tuning != null && _tuning!.$1 != it) _stopTuning();
    _pump();
  }

  void _changed(PrepItem it, {bool cropMoved = false}) {
    it._version += 1;
    it._renderSettle?.cancel();
    it._renderSettle = Timer(cropMoved ? settleCrop : settleAdjust, _pump);
    if (cropMoved) {
      it
        .._cropVersion += 1
        .._guess = it.auto ?? it._guess
        ..auto = null;
      it._tuneSettle?.cancel();
      it._tuneSettle = Timer(settleTune, _pump);
      if (_tuning?.$1 == it) _stopTuning();
    }
    notifyListeners();
    _pump();
  }

  void _stopTuning() {
    _tuning?.$2.cancel();
    _tuning = null;
  }

  void _pump() {
    if (_disposed) return;
    _pumpRender();
    _pumpTune();
  }

  /// The next photo needing work: the one in the editor first, then in order.
  PrepItem? _next(bool Function(PrepItem) needs) {
    if (focus != null && needs(focus!)) return focus;
    for (final it in items) {
      if (needs(it)) return it;
    }
    return null;
  }

  void _pumpRender() {
    if (_rendering) return;
    final it = _next((i) => i._needsRender && i._settledForRender);
    if (it != null) unawaited(_render(it));
  }

  Future<void> _render(PrepItem it) async {
    _rendering = true;
    final version = it._version, crop = it._cropVersion, settings = it._settings;
    try {
      final image = await _engine.render(_job(it, settings), model.palette);
      if (_disposed) return;
      // Keep it while the crop still matches, even if a slider moved meanwhile.
      if (it._cropVersion == crop) {
        it
          .._preview = image
          .._previewCrop = crop
          .._previewVersion = version
          .._previewSettings = settings;
      }
    } catch (e) {
      debugPrint('preview failed: $e');
      // Don't retry forever; Upload reports real failures.
      it
        .._previewVersion = version
        .._previewSettings = settings;
    } finally {
      _rendering = false;
    }
    if (_disposed) return;
    notifyListeners();
    _pump();
  }

  void _pumpTune() {
    if (_tuning != null) return;
    final it = _next((i) => i._needsTuning && i._settledForTune);
    if (it == null) return;
    final crop = it._cropVersion;
    final tuning = _engine.tune(_job(it, null));
    _tuning = (it, tuning);
    tuning.result.then((settings) {
      if (_disposed || !identical(_tuning?.$2, tuning)) return;
      _tuning = null;
      if (it._cropVersion == crop) {
        it
          ..auto = settings
          .._guess = settings;
        notifyListeners();
      }
      _pump();
    }, onError: (Object e) {
      if (_disposed || !identical(_tuning?.$2, tuning)) return;
      debugPrint('tuning failed: $e');
      _tuning = null;
      // Keep the quick look; Upload runs the search again and reports real failures.
      it._tuneFailedCrop = crop;
      _pump();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final it in items) {
      it._renderSettle?.cancel();
      it._tuneSettle?.cancel();
    }
    _stopTuning();
    super.dispose();
  }
}

// The session's own rotate() shadows resize.dart's.
(Uint8List, int, int) _rotate90(Uint8List rgba, int w, int h) => rotate(rgba, w, h, 1);

Future<ui.Image> _decode(Uint8List rgba, int w, int h) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}
