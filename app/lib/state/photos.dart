import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_error.dart';
import '../data/frame_link.dart';
import '../data/models.dart';
import '../data/photos.dart';
import '../imaging/palette.dart';
import '../imaging/pipeline.dart';
import 'providers.dart';

/// Where downloaded photos are cached (set in main from path_provider; null in tests).
final cacheRootProvider = Provider<Directory?>((ref) => null);

/// Overridable for tests.
final photosRepositoryProvider = Provider.family<PhotosRepository, FrameAddress>((ref, a) {
  final root = ref.watch(cacheRootProvider);
  final conn = ref.watch(framesRepositoryProvider).connection(a);
  return PhotosRepository(conn, cacheDir: root == null ? null : Directory('${root.path}/images/${a.ref}'));
});

/// The frame's model and its palette.
class FrameModel {
  const FrameModel(this.model, this.palette);

  final DeviceModel model;
  final Palette palette;

  double get aspect => model.width / model.height;
}

final frameModelProvider = FutureProvider.family<FrameModel, FrameAddress>((ref, a) async {
  final view = await ref.watch(frameViewProvider(a).future);
  final summary = view.summary;
  if (summary == null) throw view.error ?? const ApiException('unknown', 'Frame unavailable.');
  final m = await ref.read(photosRepositoryProvider(a)).model(summary.frame.modelId);
  return FrameModel(m, Palette.fromJson(m.palette));
});

/// Ready photos in the frame's order.
final photosProvider = AsyncNotifierProvider.family<PhotosNotifier, List<FrameImage>, FrameAddress>(PhotosNotifier.new);

class PhotosNotifier extends AsyncNotifier<List<FrameImage>> {
  PhotosNotifier(this.address);

  final FrameAddress address;

  PhotosRepository get _repo => ref.read(photosRepositoryProvider(address));

  @override
  Future<List<FrameImage>> build() => _repo.list();

  Future<void> refresh() async {
    state = AsyncData(await _repo.list());
    ref.invalidate(frameViewProvider(address));
  }

  void added(FrameImage image) {
    final list = [...?state.value, image]..sort((a, b) => a.position.compareTo(b.position));
    state = AsyncData(list);
    ref.invalidate(frameViewProvider(address));
  }

  /// Deletes [ids]; the grid updates straight away and is restored on failure.
  Future<void> delete(List<String> ids) async {
    final before = state.value ?? [];
    state = AsyncData([for (final i in before) if (!ids.contains(i.id)) i]);
    try {
      await _repo.delete(ids);
      ref.invalidate(frameViewProvider(address));
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Moves one photo from index [from] so it ends up at index [to].
  Future<void> move(int from, int to) async {
    final list = [...?state.value];
    if (from == to) return;
    final image = list.removeAt(from);
    list.insert(to, image);
    final before = state.value;
    state = AsyncData(list);
    try {
      await _repo.reorder(image.id, to == 0 ? null : list[to - 1].id);
      ref.invalidate(frameViewProvider(address));
    } catch (_) {
      state = AsyncData(before ?? []);
      rethrow;
    }
  }
}

/// A photo recoloured to the panel's calibrated colours, for display.
final displayBytesProvider = FutureProvider.family<Uint8List, (FrameAddress, FrameImage)>((ref, key) async {
  final (a, image) = key;
  final model = await ref.watch(frameModelProvider(a).future);
  return ref.read(photosRepositoryProvider(a)).displayBytes(image, model.palette);
});

// ── Upload queue ──

enum UploadStatus { waiting, processing, uploading, done, failed }

class UploadItem {
  const UploadItem(this.id, this.job, {this.status = UploadStatus.waiting, this.progress = 0, this.error, this.preview});

  final int id;
  final PhotoJob job;
  final UploadStatus status;
  final double progress;
  final ApiException? error;

  /// Palette indices once processed (drawn as the placeholder tile).
  final Uint8List? preview;

  UploadItem copyWith({UploadStatus? status, double? progress, ApiException? error, Uint8List? preview, bool clearError = false}) =>
      UploadItem(id, job,
          status: status ?? this.status,
          progress: progress ?? this.progress,
          error: clearError ? null : (error ?? this.error),
          preview: preview ?? this.preview);
}

/// In-memory queue per frame (D3): processes and uploads one photo at a time.
final uploadQueueProvider = NotifierProvider.family<UploadQueue, List<UploadItem>, FrameAddress>(UploadQueue.new);

class UploadQueue extends Notifier<List<UploadItem>> {
  UploadQueue(this.address);

  final FrameAddress address;
  var _nextId = 0;
  var _running = false;

  /// Photos already on the frame, reported once per batch ("1 photo was already…").
  var duplicates = 0;

  @override
  List<UploadItem> build() => const [];

  void addAll(List<PhotoJob> jobs) {
    state = [...state, for (final j in jobs) UploadItem(_nextId++, j)];
    _run();
  }

  void retry(int id) {
    _update(id, (i) => i.copyWith(status: UploadStatus.waiting, progress: 0, clearError: true));
    _run();
  }

  void retryAll() {
    state = [for (final i in state) i.status == UploadStatus.failed ? i.copyWith(status: UploadStatus.waiting, clearError: true) : i];
    _run();
  }

  void remove(int id) => state = [for (final i in state) if (i.id != id) i];

  void _update(int id, UploadItem Function(UploadItem) f) => state = [for (final i in state) i.id == id ? f(i) : i];

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = state.where((i) => i.status == UploadStatus.waiting).firstOrNull;
        if (next == null) break;
        await _process(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _process(UploadItem item) async {
    _update(item.id, (i) => i.copyWith(status: UploadStatus.processing));
    try {
      final job = item.job;
      final prepared = await Isolate.run(() => preparePhoto(job));
      _update(item.id, (i) => i.copyWith(status: UploadStatus.uploading, preview: prepared.indices));
      final image = await ref.read(photosRepositoryProvider(address)).upload(
            prepared.png,
            prepared.sha256,
            prepared.width,
            prepared.height,
            onProgress: (p) => _update(item.id, (i) => i.copyWith(progress: p)),
          );
      ref.read(photosProvider(address).notifier).added(image);
      remove(item.id);
    } on ApiException catch (e) {
      if (e.code == 'duplicate_image') {
        duplicates++;
        remove(item.id);
        return;
      }
      _update(item.id, (i) => i.copyWith(status: UploadStatus.failed, error: e));
      // Storage full: stop the queue; everything left waits for the person.
      if (e.code == 'quota_exceeded') {
        state = [
          for (final i in state) i.status == UploadStatus.waiting ? i.copyWith(status: UploadStatus.failed, error: e) : i,
        ];
      }
    } catch (e) {
      _update(item.id, (i) => i.copyWith(status: UploadStatus.failed, error: ApiException('unknown', '$e')));
    }
  }
}

/// user_id → display name, for "Added by …".
final memberNamesProvider = FutureProvider.family<Map<String, String>, FrameAddress>((ref, a) async {
  final conn = ref.read(framesRepositoryProvider).connection(a);
  return conn.guard(() async {
    final rows = await conn.client.from('members').select('user_id, display_name');
    return {for (final r in rows) r['user_id'] as String: r['display_name'] as String};
  });
});
