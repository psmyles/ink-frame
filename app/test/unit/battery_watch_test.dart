// The low-battery notification (PLAN.md §15): each phone's choice, its read-only
// watch token, and the background check that notifies once per low spell.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_frame/battery/background.dart';
import 'package:ink_frame/battery/battery_watch.dart';
import 'package:ink_frame/battery/notifications.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/secure_store.dart';

import '../widget/fake_frame_api.dart';
import '../widget/frame_screen_test.dart' show alice, kitchen, priya;

/// `GET`/`DELETE /app-api/watch` for Kitchen.
class FakeWatchServer {
  Map<String, Object?> frame = {'name': 'Kitchen', 'connected': true, 'battery_pct': 80, 'low_battery_pct': 20, 'last_seen_at': null, 'sync_interval_s': 86400};
  final valid = <String>{};
  final revoked = <String>[];
  var offline = false;
  var deleted = false;

  late final client = MockClient((req) async {
    if (offline) throw http.ClientException('offline');
    if (deleted) return http.Response('Project removed.', 410);
    expect(req.url.toString(), '${kitchen.url}/functions/v1/app-api/watch');
    final token = req.headers['x-watch-token'];
    if (req.method == 'DELETE') {
      revoked.add(token!);
      valid.remove(token);
      return http.Response('', 204);
    }
    if (!valid.contains(token)) {
      return http.Response(jsonEncode({'error': {'code': 'invalid_watch_token', 'message': ''}}), 401);
    }
    return http.Response(jsonEncode(frame), 200);
  });
}

class FakeNotifications implements Notifications {
  FakeNotifications({this.allow = true});

  final bool allow;
  final shown = <String>[];
  var asked = 0;

  @override
  Future<bool> allowed() async => allow;

  @override
  Future<bool> request() async {
    asked++;
    return allow;
  }

  @override
  Future<void> show(int id, String title, String body, {required String channel}) async => shown.add('$title | $body');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

FrameSummary summary(bool owner) => FakeFrameApi().view(owner ? priya : alice, priya).summary!;

void main() {
  late MemoryStore store;
  late FakeWatchServer server;
  late FakeFrameApi api;
  late BatteryWatch watch;

  setUp(() {
    store = MemoryStore();
    server = FakeWatchServer();
    api = FakeFrameApi();
    watch = BatteryWatch(store, httpClient: server.client);
  });

  Future<void> owned() async {
    await watch.sync(kitchen, summary(true), api);
    server.valid.addAll(api.watchTokens);
  }

  test('on by default for the owner, off for others; once per run', () async {
    await watch.sync(kitchen, summary(false), api);
    expect(api.watchTokens, isEmpty);
    expect(await watch.choice(kitchen), isNull);

    final fresh = BatteryWatch(store, httpClient: server.client);
    await fresh.sync(kitchen, summary(true), api);
    await fresh.sync(kitchen, summary(true), api);
    expect(api.watchTokens, hasLength(1));
  });

  test('turning it off revokes the token; on gets a new one', () async {
    await owned();
    await watch.choose(kitchen, false, api);
    expect(server.revoked, [api.watchTokens.single]);
    expect(await watch.choice(kitchen), isFalse);
    expect(await watch.check(), isEmpty);

    await watch.choose(kitchen, true, api);
    expect(api.watchTokens, hasLength(2));
  });

  test('a frame from before watch tokens: unavailable until the owner updates it', () async {
    api.noWatchTokens = true;
    await watch.sync(kitchen, summary(true), api);
    expect(await watch.available(kitchen), isFalse);

    api.noWatchTokens = false;
    await watch.updated(kitchen);
    expect(await watch.available(kitchen), isTrue);
    await watch.sync(kitchen, summary(true), api);
    expect(api.watchTokens, hasLength(1));
  });

  test('notifies once when the battery goes low, again after it was charged', () async {
    await owned();
    expect(await watch.check(), isEmpty);

    server.frame['battery_pct'] = 15;
    final low = await watch.check();
    expect([for (final f in low) (f.name, f.batteryPct)], [('Kitchen', 15)]);
    server.frame['battery_pct'] = 12;
    expect(await watch.check(), isEmpty, reason: 'still the same low spell');

    server.frame['battery_pct'] = 95;
    expect(await watch.check(), isEmpty);
    server.frame['battery_pct'] = 18;
    expect(await watch.check(), hasLength(1));
  });

  test('no warning level, or no hardware: nothing to say', () async {
    await owned();
    server.frame
      ..['battery_pct'] = 5
      ..['low_battery_pct'] = null;
    expect(await watch.check(), isEmpty);
    server.frame
      ..['low_battery_pct'] = 20
      ..['connected'] = false;
    expect(await watch.check(), isEmpty);
  });

  test('offline: tried again next time; left the frame: stops checking', () async {
    await owned();
    server.frame['battery_pct'] = 10;
    server.offline = true;
    expect(await watch.check(), isEmpty);
    server.offline = false;
    expect(await watch.check(), hasLength(1));

    server.valid.clear(); // removed from the frame
    server.frame['battery_pct'] = 9;
    expect(await watch.check(), isEmpty);
    expect(jsonDecode(store.values['battery_watch']!), isEmpty);
  });

  test('the frame was deleted: stops checking', () async {
    await owned();
    server.deleted = true;
    expect(await watch.check(), isEmpty);
    expect(jsonDecode(store.values['battery_watch']!), isEmpty);
  });

  test('signing out forgets the frame and revokes its token', () async {
    await owned();
    await watch.forgetAll();
    expect(server.revoked, api.watchTokens);
    expect(store.values['battery_watch'], isNull);
  });

  test('the background check notifies in plain words', () async {
    await owned();
    server.frame['battery_pct'] = 15;
    final notifications = FakeNotifications();
    await checkBatteries(watch, notifications);
    expect(notifications.shown, ["Kitchen: the frame's battery is low | 15 % left. Charge it soon so it keeps showing new photos."]);
  });

  test('desktops have no background checks', () async {
    final desktop = BatteryWatch(store, httpClient: server.client, supported: false);
    await desktop.sync(kitchen, summary(true), api);
    expect(api.watchTokens, isEmpty);
    expect(await desktop.choice(kitchen), isNull);
  });
}
