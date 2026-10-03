import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_frame/data/frame_directory.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/secure_store.dart';

/// The directory (shared/api/directory.yaml) in memory. An ID token here is just
/// the account's name; "bad" is refused.
class FakeDirectoryServer {
  final accounts = <String, List<FrameAddress>>{};
  final tokens = <String, String>{};
  final calls = <String>[];
  var offline = false;
  var _n = 0;

  late final client = MockClient((req) async {
    if (offline) throw http.ClientException('offline');
    final path = req.url.path.replaceFirst('/v1', '');
    calls.add('${req.method} $path');
    final body = req.body.isEmpty ? const <String, dynamic>{} : jsonDecode(req.body) as Map<String, dynamic>;
    http.Response json(int status, Object body) => http.Response(jsonEncode(body), status);
    http.Response error(int status, String code) => json(status, {'error': {'code': code, 'message': code}});
    List<Map<String, String>> listOf(String a) => [for (final f in accounts[a] ?? const <FrameAddress>[]) f.toJson()];

    if (path == '/sign-in') {
      final account = body['id_token'] as String;
      if (account == 'bad') return error(401, 'invalid_id_token');
      final token = 'tok${_n++}';
      tokens[token] = account;
      return json(200, {'token': token, 'frames': listOf(account)});
    }
    final account = tokens[req.headers['Authorization']?.replaceFirst('Bearer ', '')];
    if (account == null) return error(401, 'invalid_token');
    switch ('${req.method} $path') {
      case 'POST /frames':
        final list = accounts.putIfAbsent(account, () => []);
        final remove = [for (final u in body['remove'] as List? ?? const []) u as String];
        list.removeWhere((f) => remove.contains(f.url));
        for (final f in body['add'] as List? ?? const []) {
          final a = FrameAddress.fromJson(f as Map<String, dynamic>);
          list.removeWhere((x) => x.url == a.url);
          list.add(a);
        }
        return json(200, {'frames': listOf(account)});
      case 'POST /sign-out':
        tokens.removeWhere((t, _) => req.headers['Authorization'] == 'Bearer $t');
        return http.Response('', 204);
      case 'DELETE /me':
        accounts.remove(account);
        tokens.removeWhere((_, a) => a == account);
        return http.Response('', 204);
    }
    return error(404, 'not_found');
  });

  FrameDirectory directory(KeyValueStore store) => FrameDirectory(store, httpClient: client, baseUrl: 'https://dir.test');
}
