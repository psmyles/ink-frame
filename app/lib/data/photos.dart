import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../imaging/palette.dart';
import '../imaging/png_palette.dart';
import 'api_error.dart';
import 'frame_connection.dart';
import 'models.dart';

/// Photos on one frame: list, download (cached), upload, delete, reorder
/// (app-flow §3, shared/api/openapi.yaml). Reads go straight to the tables under
/// RLS; writes go through app-api.
class PhotosRepository {
  PhotosRepository(this.conn, {this.cacheDir, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final FrameConnection conn;

  /// Where downloaded PNGs are kept (`<id>.png`); null keeps them in memory only.
  final Directory? cacheDir;
  final http.Client _http;
  final _memory = <String, Uint8List>{};

  /// Ready photos in the frame's order.
  Future<List<FrameImage>> list() => conn.guard(() async {
        final rows = await conn.client
            .from('images')
            .select('id, uploaded_by, storage_path, bytes, position, created_at')
            .eq('status', 'ready')
            .order('position', ascending: true);
        return [for (final r in rows) FrameImage.fromJson(r)];
      });

  /// The frame's model and palette.
  Future<DeviceModel> model(String modelId) => conn.guard(() async {
        final row = await conn.client
            .from('device_models')
            .select('id, name, width, height, palette_id, palettes(colors)')
            .eq('id', modelId)
            .single();
        return DeviceModel.fromJson(row);
      });

  /// The stored PNG (device colours), from memory, disk, or a signed URL.
  Future<Uint8List> download(FrameImage image) async {
    final hit = _memory[image.id];
    if (hit != null) return hit;
    final file = cacheDir == null ? null : File('${cacheDir!.path}/${image.id}.png');
    if (file != null && file.existsSync()) return _memory[image.id] = await file.readAsBytes();

    final url = await conn.guard(() => conn.client.storage.from('frame-images').createSignedUrl(image.storagePath, 600));
    final res = await conn.guard(() => _http.get(Uri.parse(url)).timeout(const Duration(seconds: 60)));
    if (res.statusCode != 200) throw ApiException.fromResponse(res.statusCode, null);
    final bytes = res.bodyBytes;
    if (file != null) {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    return _memory[image.id] = bytes;
  }

  /// The PNG recoloured to the panel's calibrated colours, for display.
  Future<Uint8List> displayBytes(FrameImage image, Palette palette) async =>
      recolorPng(await download(image), palette.deviceColors, palette.colors);

  /// request-upload → PUT → finalize.
  /// Throws [ApiException] (e.g. `duplicate_image`, `quota_exceeded`).
  Future<FrameImage> upload(Uint8List png, String sha256, int width, int height) async {
    final r = await conn.callApi('POST', '/images/request-upload',
        body: {'sha256': sha256, 'bytes': png.length, 'width': width, 'height': height}) as Map<String, dynamic>;
    final imageId = r['image_id'] as String;

    await conn.guard(() async {
      final res = await _http
          .put(Uri.parse(r['upload_url'] as String), headers: {'Content-Type': 'image/png'}, body: png)
          .timeout(const Duration(seconds: 120));
      if (res.statusCode >= 300) throw ApiException('upload_failed', 'Upload failed (${res.statusCode}).', status: res.statusCode);
    });

    final done = await conn.callApi('POST', '/images/finalize', body: {'image_id': imageId}) as Map<String, dynamic>;
    final image = FrameImage.fromJson(done);
    _memory[image.id] = png;
    return image;
  }

  Future<void> delete(List<String> ids) async {
    await conn.callApi('POST', '/images/delete', body: {'image_ids': ids});
    for (final id in ids) {
      _memory.remove(id);
      final f = cacheDir == null ? null : File('${cacheDir!.path}/$id.png');
      if (f != null && f.existsSync()) await f.delete();
    }
  }

  /// Owner only: puts [imageId] right after [afterId], or first when null.
  Future<void> reorder(String imageId, String? afterId) =>
      conn.callApi('POST', '/images/reorder', body: {'image_id': imageId, 'after_image_id': afterId});
}
