// Renders screens to PNGs for a visual check (not part of CI):
//   PREVIEW=1 flutter test test/preview --update-goldens   → test/preview/out/*.png (gitignored)
@Tags(['preview'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';


import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/frame/frame_screen.dart';
import 'package:ink_frame/imaging/dither.dart' show preview;
import 'package:ink_frame/imaging/auto.dart' show faithful;
import 'package:ink_frame/imaging/palette.dart';
import 'package:ink_frame/features/people/people_screen.dart';
import 'package:ink_frame/features/prepare/frame_canvas.dart';
import 'package:ink_frame/features/settings/settings_screen.dart';
import 'package:ink_frame/features/storage/storage_screen.dart';
import 'package:ink_frame/widgets/side_panel.dart';
import 'package:ink_frame/features/prepare/prepare_session.dart';
import 'package:ink_frame/features/prepare/source_photo.dart';
import 'package:ink_frame/imaging/pipeline.dart';
import 'package:ink_frame/imaging/png_encoder.dart';
import 'package:ink_frame/imaging/png_palette.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/photos.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';

import '../widget/fake_frame_api.dart';
import '../widget/frame_screen_test.dart' as fs;
import '../widget/prepare_screen_test.dart' as ps;
import 'package:ink_frame/features/prepare/prepare_screen.dart';
import '../widget/layout_test.dart' as layout;
import '../widget/more_frames_test.dart' as more;
import '../unit/battery_watch_test.dart' show FakeNotifications, FakeWatchServer;
import '../unit/fake_bluetooth.dart';
import '../unit/fake_platform.dart' show testBundle;
import 'package:ink_frame/battery/battery_watch.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/connect/connect_frame_screen.dart';
import 'package:ink_frame/state/connect_frame.dart';
import 'package:ink_frame/state/setup.dart';

Future<void> loadFonts() async {
  // flutter test sets FLUTTER_ROOT.
  final fonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('$fonts/Roboto-$w.ttf');
    if (f.existsSync()) roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

// Spectra 6 (the presets' calibrated colours).
final pal = Palette.fromJson({
  'id': 'spectra6',
  'colors': [
    for (final (n, c, d) in [('black', '#29222D', '#000000'), ('white', '#C5CDCB', '#ffffff'), ('blue', '#224D98', '#0000ff'),
      ('green', '#486F5B', '#00ff00'), ('red', '#76231F', '#ff0000'), ('yellow', '#D5BD14', '#ffff00')])
      {'name': n, 'color': c, 'deviceColor': d},
  ],
});

void main() {
  if (Platform.environment['PREVIEW'] == null) {
    test('previews', () {}, skip: 'Set PREVIEW=1 and pass --update-goldens');
    return;
  }
  setUpAll(loadFonts);

  Future<void> shot(WidgetTester tester, String name) =>
      expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));

  testWidgets('welcome', (t) async {
    await layout.pumpApp(t, const Size(400, 820));
    await shot(t, 'welcome');
  });
  testWidgets('home narrow', (t) async {
    await layout.pumpApp(t, const Size(400, 820), frames: [layout.kitchen, layout.grandma]);
    await shot(t, 'home_narrow');
  });
  testWidgets('home wide', (t) async {
    await layout.pumpApp(t, const Size(1200, 760), frames: [layout.kitchen, layout.grandma]);
    await t.tap(find.text("Grandma's"));
    await t.pumpAndSettle();
    await shot(t, 'home_wide');
  });

  testWidgets('frame grid with real photos', (t) async {
    final dir = Platform.environment['PHOTOS'];
    if (dir == null) return;
    final files = (Directory(dir).listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path))).take(5).toList();
    final shown = <String, Uint8List>{};
    final images = <FrameImage>[];
    await t.runAsync(() async {
      for (final (i, f) in files.indexed) {
        final src = img.decodeImage(f.readAsBytesSync())!.convert(numChannels: 4);
        final p = preparePhoto(
          PhotoJob(rgba: src.getBytes(order: img.ChannelOrder.rgba), width: src.width, height: src.height, outWidth: 800, outHeight: 480, palette: pal),
          zopfliIterations: 0,
        );
        shown['p$i'] = recolorPng(PngEncoder.encode(p.indices, 800, 480, pal.deviceColors, zopfli: 0).bytes, pal.deviceColors, pal.colors);
        images.add(fs.photo('p$i', i.isEven ? 'alice' : 'priya', i + 1));
      }
    });
    t.view.physicalSize = const Size(420, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        frameViewProvider(fs.kitchen).overrideWith((ref) async => fs.view(me: fs.alice)),
        photosProvider.overrideWith2((a) => fs.FakePhotos(a, images)),
        frameModelProvider.overrideWith((ref, a) async =>
            FrameModel(const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}), pal)),
        displayBytesProvider.overrideWith((ref, key) async => shown[key.$2.id]!),
        memberNamesProvider.overrideWith((ref, a) async => {'alice': 'Alice', 'priya': 'Priya'}),
      ],
      child: MaterialApp(
        theme: InkTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FrameScreen(address: fs.kitchen),
      ),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await t.pumpAndSettle();
    for (final e in find.byType(Image).evaluate()) {
      await t.runAsync(() => precacheImage((e.widget as Image).image, e));
    }
    await t.pumpAndSettle();
    await shot(t, 'frame_grid');
  });

  // The Prepare flow at phone, phone-landscape and desktop sizes, in dark mode.
  // Uses PHOTOS (real photos, frame looks rendered by the real pipeline) when set.
  Future<void> pumpPrepare(WidgetTester t, Size size) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final dir = Platform.environment['PHOTOS'];
    final photos = <SourcePhoto>[];
    final looks = <Uint8List, ui.Image>{};
    if (dir != null) {
      final files = (Directory(dir).listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path))).take(5);
      for (final f in files) {
        final p = await t.runAsync(() => SourcePhoto.decode(f.path, f.readAsBytesSync()));
        photos.add(p!);
        final job = PhotoJob(rgba: p.rgba, width: p.width, height: p.height, outWidth: 800, outHeight: 480, palette: pal);
        final (indices, _) = ditherPhoto(job);
        looks[p.rgba] = await ps.decode(t, preview(indices, pal), 800, 480);
      }
    } else {
      photos.addAll([await ps.sourcePhoto(t, 1200, 900), await ps.sourcePhoto(t, 900, 1200)]);
    }
    await t.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        frameModelProvider.overrideWith((ref, a) async =>
            FrameModel(const DeviceModel(id: 'm', name: 'm', width: 800, height: 480, palette: {}), pal)),
        // Precomputed centre-crop looks (the photos aren't moved here).
        previewEngineProvider.overrideWithValue(PreviewEngine(
          render: (job, palette) => looks[job.rgba] == null ? Completer<ui.Image>().future : Future.value(looks[job.rgba]),
          tune: (job) => Tuning(Future.value(faithful), () {}),
        )),
      ],
      child: MaterialApp(
        theme: InkTheme.light(),
        darkTheme: InkTheme.dark(),
        themeMode: ThemeMode.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PrepareScreen(address: fs.kitchen, photos: photos),
      ),
    ));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
  }

  for (final (name, size) in const [('phone', Size(380, 860)), ('landscape', Size(860, 400)), ('desktop', Size(1300, 820))]) {
    testWidgets('prepare $name', (t) async {
      await pumpPrepare(t, size);
      await shot(t, 'prepare_${name}_overview');
      await t.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await t.pump(const Duration(seconds: 1));
      await shot(t, 'prepare_${name}_overview_end');
      await t.drag(find.byType(CustomScrollView), const Offset(0, 4000));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Edit').first);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      await shot(t, 'prepare_${name}_editor');
      // Mid-drag: the photo itself, with the parts that will be cut off dimmed.
      final g = await t.startGesture(t.getCenter(find.byType(FrameCanvas)));
      await g.moveBy(const Offset(0, 30));
      await t.pump();
      await shot(t, 'prepare_${name}_dragging');
      await g.up();
      await t.pump(const Duration(seconds: 1));
    });
  }

  // Phase 3d screens with the fake API, dark mode.
  const me = Member(userId: 'priya', role: Role.owner, displayName: 'Priya');
  const alice = Member(userId: 'alice', role: Role.member, displayName: 'Alice');
  const bob = Member(userId: 'bob', role: Role.member, displayName: 'Bob');
  FakeFrameApi api() => FakeFrameApi(
        members: [me, alice, bob],
        invites: [Invite(id: 'i1', expiresAt: DateTime(2026, 10, 10), maxUses: 10, uses: 2)],
        usage: sampleUsage(users: [
          const UsageEntry(images: 30, bytes: 200 * 1024 * 1024, userId: 'priya'),
          const UsageEntry(images: 12, bytes: 80 * 1024 * 1024, userId: 'alice'),
          const UsageEntry(images: 6, bytes: 32 * 1024 * 1024, userId: 'bob'),
        ]),
      );
  const phone = Size(400, 860);

  testWidgets('3d settings owner', (t) async {
    await pumpFrameScreen(t, () => const SettingsScreen(address: fs.kitchen),
        address: fs.kitchen, me: me, owner: me, api: api(), size: const Size(400, 1250), dark: true);
    await shot(t, '3d_settings_owner');
  });
  testWidgets('3d settings member', (t) async {
    await pumpFrameScreen(t, () => const SettingsScreen(address: fs.kitchen),
        address: fs.kitchen, me: alice, owner: me, api: api(), size: phone, dark: true);
    await shot(t, '3d_settings_member');
  });
  testWidgets('3d people', (t) async {
    await pumpFrameScreen(t, () => const PeopleScreen(address: fs.kitchen),
        address: fs.kitchen, me: me, owner: me, api: api(), size: phone, dark: true);
    await shot(t, '3d_people');
    await t.tap(find.text('Invite someone'));
    await t.pumpAndSettle();
    await shot(t, '3d_invite_sheet');
  });
  testWidgets('3d storage', (t) async {
    await pumpFrameScreen(t, () => const StorageScreen(address: fs.kitchen),
        address: fs.kitchen, me: me, owner: me, api: api(), size: phone, dark: true);
    await shot(t, '3d_storage');
  });
  // 3f/3g screens, dark mode.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('3f connect the frame', (t) async {
    final fake = FakeFrameApi(frame: frameJson(connected: false), members: [me]);
    final hw = FakeHardware(claim: (p, info) async {
      fake.claimed(info.hwId);
      return null;
    });
    await pumpFrameScreen(
      t,
      () => Builder(
        builder: (c) => Scaffold(body: TextButton(onPressed: () => openConnectFrame(c, fs.kitchen), child: const Text('open'))),
      ),
      address: fs.kitchen, me: me, owner: me, api: fake, size: phone, dark: true,
      overrides: [
        frameBluetoothProvider.overrideWithValue(FakeBluetooth([hw])),
        backendBundleProvider.overrideWith((ref) async => testBundle),
      ],
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await shot(t, '3f_connect_ready');
    await t.tap(find.text('Find the frame'));
    await settle(t);
    await t.tap(find.text('Home'));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, 'Wi-Fi password'), 'correct horse');
    await t.pump();
    await shot(t, '3f_connect_wifi');
    await t.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(t);
    await shot(t, '3f_connect_done');
  });

  testWidgets('3g settings: battery notification', (t) async {
    await pumpFrameScreen(t, () => const SettingsScreen(address: fs.kitchen),
        address: fs.kitchen, me: me, owner: me, api: api(), size: const Size(400, 1400), dark: true,
        overrides: [
          batteryWatchProvider.overrideWithValue(BatteryWatch(MemoryStore(), httpClient: FakeWatchServer().client)),
          notificationsProvider.overrideWithValue(FakeNotifications()),
        ]);
    await shot(t, '3g_settings_notify');
  });

  testWidgets('3g home: more frames on your account', (t) async {
    await more.open(t);
    await t.pumpWidget(Container());
    await more.open(t, dark: true);
    await shot(t, '3g_home_more');
  });

  testWidgets('3d desktop side panel', (t) async {
    await pumpFrameScreen(
      t,
      () => Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Kitchen')),
          body: Center(
            child: FilledButton(
              onPressed: () => openPanel<void>(context, (_) => const SettingsScreen(address: fs.kitchen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      address: fs.kitchen, me: me, owner: me, api: api(), size: const Size(1300, 820), dark: true,
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await shot(t, '3d_desktop_panel');
  });
}
