// The real upload queue (the widget tests swap it for a recorder): processes each
// photo in an isolate, uploads it, and adds it to the grid.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/photos.dart';
import 'package:ink_frame/imaging/pipeline.dart';
import 'package:ink_frame/state/photos.dart';

import '../widget/frame_screen_test.dart' show FakePhotos, kitchen, palette;

class FakeRepo implements PhotosRepository {
  final uploads = <(Uint8List, String, int, int)>[];
  ApiException? failWith;

  @override
  Future<FrameImage> upload(Uint8List png, String sha256, int width, int height) async {
    if (failWith != null) throw failWith!;
    uploads.add((png, sha256, width, height));
    return FrameImage.fromJson({
      'id': 'img${uploads.length}',
      'uploaded_by': 'me',
      'bytes': png.length,
      'position': uploads.length,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PhotoJob job(int seed) {
  const w = 600, h = 400;
  final rgba = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    rgba.setAll(i * 4, [(i % w + seed * 40) % 256, (i ~/ w) * 255 ~/ h, 90, 255]);
  }
  return PhotoJob(rgba: rgba, width: w, height: h, outWidth: 800, outHeight: 480, palette: palette);
}

Future<void> drained(ProviderContainer c) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (c.read(uploadQueueProvider(kitchen)).any((i) => i.status != UploadStatus.failed)) {
    if (DateTime.now().isAfter(deadline)) fail('queue did not finish');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late FakeRepo repo;
  late ProviderContainer c;

  setUp(() {
    repo = FakeRepo();
    c = ProviderContainer(overrides: [
      photosRepositoryProvider.overrideWith((ref, a) => repo),
      photosProvider.overrideWith2((a) => FakePhotos(a, const [])),
    ]);
    addTearDown(c.dispose);
  });

  test('processes and uploads each photo, then adds it to the grid', () async {
    await c.read(photosProvider(kitchen).future);
    c.listen(uploadQueueProvider(kitchen), (_, _) {});
    c.read(uploadQueueProvider(kitchen).notifier).addAll([job(0), job(1)]);
    await drained(c);
    final q = c.read(uploadQueueProvider(kitchen));
    expect(q.map((i) => i.error?.message), isEmpty);
    expect(repo.uploads, hasLength(2));
    expect(repo.uploads.first.$3, 800);
    expect(c.read(photosProvider(kitchen)).value!.map((i) => i.id), ['img1', 'img2']);
  });

  test('a failure keeps the photo with its reason; storage full stops the rest', () async {
    await c.read(photosProvider(kitchen).future);
    c.listen(uploadQueueProvider(kitchen), (_, _) {});
    repo.failWith = const ApiException('quota_exceeded', 'Storage is full.');
    c.read(uploadQueueProvider(kitchen).notifier).addAll([job(0), job(1)]);
    await drained(c);
    final q = c.read(uploadQueueProvider(kitchen));
    expect(q.map((i) => i.error?.code), ['quota_exceeded', 'quota_exceeded']);
  });
}
