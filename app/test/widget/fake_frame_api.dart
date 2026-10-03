// A FrameApi that keeps the frame, people, invites and usage in memory and records
// every write, for the Settings / People / Storage / Account widget tests.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ink_frame/data/api_error.dart';
import 'package:ink_frame/data/frame_api.dart';
import 'package:ink_frame/data/frame_connection.dart';
import 'package:ink_frame/data/frame_directory.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/frame_admin.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';

const gb = 1024 * 1024 * 1024;

Map<String, dynamic> frameJson({String name = 'Kitchen', bool inOrder = false, int? battery = 80}) => {
      'id': 'f',
      'name': name,
      'model_id': 'reterminal-e1002',
      'connected': true,
      'up_to_date': true,
      'fw_version': '1.0.0',
      'last_seen_at': DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
      'battery_pct': battery,
      'image_interval_s': 14400,
      'display_order': inOrder ? 'sequential' : 'random',
      'sync_interval_s': 86400,
      'quiet_start': null,
      'quiet_end': null,
      'timezone': 'Asia/Kolkata',
      'low_battery_pct': 20,
    };

Usage sampleUsage({int bytes = 312 * 1024 * 1024, int images = 48, List<UsageEntry>? users}) => Usage(
      frame: UsageEntry(images: images, bytes: bytes),
      freeTierBytes: gb,
      users: users ?? [UsageEntry(images: images, bytes: bytes, userId: 'priya')],
    );

class FakeFrameApi implements FrameApi {
  FakeFrameApi({Map<String, dynamic>? frame, List<Member>? members, List<Invite>? invites, Usage? usage})
      : frame = frame ?? frameJson(),
        memberList = members ?? [],
        inviteList = invites ?? [],
        usageValue = usage ?? sampleUsage();

  /// The frame as `Frame.fromJson` reads it; writes change it.
  final Map<String, dynamic> frame;
  List<Member> memberList;
  List<Invite> inviteList;
  Usage usageValue;

  /// Every write, e.g. `settings {image_interval_s: 7200}`.
  final calls = <String>[];

  /// Thrown by the next write instead of doing it.
  ApiException? failNext;

  var _code = 0;

  void _write(String call) {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
    calls.add(call);
  }

  Frame get current => Frame.fromJson(frame);

  /// A FrameView for this frame as [me], owned by [owner].
  FrameView view(Member me, Member owner) => FrameView(summary: FrameSummary(frame: current, me: me, owner: owner));

  @override
  FrameConnection get conn => throw UnimplementedError();

  @override
  Future<Frame> updateSettings(Map<String, Object?> patch) async {
    _write('settings $patch');
    frame.addAll(patch);
    return current;
  }

  @override
  Future<Frame> rename(String name) async {
    _write('rename $name');
    frame['name'] = name;
    return current;
  }

  @override
  Future<Frame> changeModel(String modelId) async {
    _write('model $modelId');
    frame['model_id'] = modelId;
    return current;
  }

  @override
  Future<List<Member>> members() async => memberList;

  @override
  Future<List<Invite>> invites() async => inviteList;

  @override
  Future<NewInvite> createInvite({int maxUses = 1, Duration expiresIn = const Duration(days: 7)}) async {
    _write('invite $maxUses ${expiresIn.inDays}d');
    _code++;
    final invite = NewInvite(
      id: 'inv$_code',
      code: 'ABCDE-FGHJ$_code',
      expiresAt: DateTime.now().add(expiresIn),
      maxUses: maxUses,
    );
    inviteList = [Invite(id: invite.id, expiresAt: invite.expiresAt, maxUses: maxUses, uses: 0), ...inviteList];
    return invite;
  }

  @override
  Future<void> revokeInvite(String id) async {
    _write('revoke $id');
    inviteList = inviteList.where((i) => i.id != id).toList();
  }

  @override
  Future<void> removeMember(String userId) async {
    _write('remove $userId');
    memberList = memberList.where((m) => m.userId != userId).toList();
  }

  @override
  Future<void> updateMe(String displayName) async => _write('me $displayName');

  @override
  Future<void> deleteMe({bool deletePhotos = false}) async => _write('deleteMe photos=$deletePhotos');

  @override
  Future<Usage> usage() async => usageValue;
}

/// Shows [screen] for the frame at [address] as [me] (the frame reads from [api]),
/// inside a router so screens can go Home. Returns the fake API.
Future<FakeFrameApi> pumpFrameScreen(
  WidgetTester tester,
  Widget Function() screen, {
  required FrameAddress address,
  required Member me,
  required Member owner,
  FakeFrameApi? api,
  Size size = const Size(420, 900),
  KeyValueStore? store,
  bool dark = false,
  FrameDirectory? directory,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = api ?? FakeFrameApi(members: [owner, if (me.userId != owner.userId) me]);
  final s = store ?? MemoryStore();
  await FramesRepository(s).add(address);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => screen()),
    GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('Home'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      storeProvider.overrideWithValue(s),
      frameApiProvider.overrideWith((ref, a) => fake),
      if (directory != null) frameDirectoryProvider.overrideWithValue(directory),
      ...overrides,
      frameViewProvider(address).overrideWith((ref) async => fake.view(me, owner)),
      memberNamesProvider.overrideWith((ref, a) async => {for (final m in fake.memberList) m.userId: m.displayName}),
      frameModelProvider.overrideWith((ref, a) async => FrameModel(
            const DeviceModel(id: 'reterminal-e1002', name: 'reTerminal E1002', width: 800, height: 480, palette: {}),
            Palette.fromJson({
              'id': 'p',
              'colors': [
                {'name': 'black', 'color': '#1F2226', 'deviceColor': '#000000'},
                {'name': 'white', 'color': '#B9C7C9', 'deviceColor': '#ffffff'},
              ],
            }),
          )),
    ],
    child: MaterialApp.router(
      theme: InkTheme.light(),
      darkTheme: InkTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}
