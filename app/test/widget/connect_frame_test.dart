// Connect the frame (app-flow §6, docs/pairing.md) against a pretend frame: find,
// pair, Wi-Fi, finishing, and the §6.2 problems.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/ble/frame_bluetooth.dart';
import 'package:ink_frame/ble/protocol.dart';
import 'package:ink_frame/features/connect/connect_frame_screen.dart';
import 'package:ink_frame/features/connect/dev_connect_screen.dart';
import 'package:ink_frame/state/connect_frame.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/state/setup.dart';

import '../unit/fake_bluetooth.dart';
import '../unit/fake_platform.dart';
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show kitchen, priya;

/// Opens Connect the frame for Kitchen (not connected yet) from a button, as the owner.
Future<FakeFrameApi> open(WidgetTester tester, FakeBluetooth bt, {FakeFrameApi? api, bool devMode = false}) async {
  final fake = api ?? FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
  await pumpFrameScreen(
    tester,
    () => Builder(
      builder: (context) => Scaffold(
        body: TextButton(onPressed: () => openConnectFrame(context, kitchen), child: const Text('open')),
      ),
    ),
    address: kitchen,
    me: priya,
    owner: priya,
    api: fake,
    size: const Size(420, 1000),
    overrides: [
      frameBluetoothProvider.overrideWithValue(bt),
      backendBundleProvider.overrideWith((ref) async => testBundle),
      devModeProvider.overrideWith(() => _DevMode(devMode)),
    ],
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

class _DevMode extends DevModeNotifier {
  _DevMode(this.on);
  final bool on;
  @override
  Future<bool> build() async => on;
}

/// Lets the flow run (spinners never settle, so no pumpAndSettle).
Future<void> run(WidgetTester tester, [Duration d = const Duration(milliseconds: 500)]) async {
  for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 50)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Find → (settle) → pair → the Wi-Fi list.
Future<void> findAndPair(WidgetTester tester) async {
  await tester.tap(find.text('Find the frame'));
  await run(tester, ConnectFrame.settle + const Duration(milliseconds: 500));
}

Future<void> joinWifi(WidgetTester tester, String ssid, String password) async {
  await tester.tap(find.text(ssid));
  await tester.pump();
  await tester.enterText(find.widgetWithText(TextField, 'Wi-Fi password'), password);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
  await run(tester);
}

/// A frame whose claims use [api]'s pairing tokens, like device-api would.
FakeHardware hardware(FakeFrameApi api, {Set<String> expired = const {}, String modelId = 'reterminal-e1002', String? frameId}) =>
    FakeHardware(
      modelId: modelId,
      frameId: frameId,
      claim: (p, info) async {
        if (!api.tokens.contains(p.pairingToken) || expired.contains(p.pairingToken)) return 'invalid_pairing_token';
        api.claimed(info.hwId);
        return null;
      },
    );

void main() {
  testWidgets('find, pair, choose Wi-Fi, finish: the frame is connected', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api);
    await open(tester, FakeBluetooth([hw]), api: api);
    expect(find.text('Get the frame ready'), findsOneWidget);
    expect(find.textContaining('Hold the green button'), findsOneWidget);
    expect(find.text('Connect with a code (developer)'), findsNothing);

    await findAndPair(tester);
    expect(hw.pairings, 1);
    expect(find.text('Which Wi-Fi should the frame use?'), findsOneWidget);
    // Strongest first.
    final names = [for (final t in tester.widgetList<ListTile>(find.byType(ListTile))) ((t.title as Text?)?.data)];
    expect(names.take(4), ['Home', 'Cafe', 'Neighbour', 'Other network…']);
    expect(find.text('Looking for networks…'), findsNothing, reason: 'the scan finished');
    expect(find.text('Look again'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect')).onPressed, isNull);

    await joinWifi(tester, 'Home', 'correct horse');
    expect(find.text('Kitchen is connected'), findsOneWidget);
    final sent = hw.provisions.single;
    expect((sent.ssid, sent.password), ('Home', 'correct horse'));
    expect(sent.apiBaseUrl, '${kitchen.url}/functions/v1');
    expect(sent.pairingToken, api.tokens.single);
    expect(api.current.connected, isTrue);
    expect(hw.bondsRemoved, 1);
    expect(hw.connected, isFalse);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the finishing checklist follows the frame', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api)..silentAfter = LinkState.claiming;
    await open(tester, FakeBluetooth([hw]), api: api);
    await findAndPair(tester);
    await joinWifi(tester, 'Home', 'correct horse');
    expect(find.text('Connecting Kitchen'), findsOneWidget);
    expect(find.text('Joining Home'), findsOneWidget);
    expect(find.text('Linking to Kitchen'), findsOneWidget);
    expect(find.text('Getting photos'), findsOneWidget);
    // Silent for too long before claiming: the connection is lost.
    await run(tester, ConnectFrame.quietLimit);
    expect(find.text('Lost the connection to the frame.'), findsOneWidget);
  });

  testWidgets('a connection that drops after claiming still counts as done', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api)..dropAfter = LinkState.claimed;
    await open(tester, FakeBluetooth([hw]), api: api);
    await findAndPair(tester);
    await joinWifi(tester, 'Home', 'correct horse');
    expect(find.text('Kitchen is connected'), findsOneWidget);
  });

  testWidgets('a wrong code says so; trying again asks again', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api)..failNextPair = LinkFailure.wrongCode;
    await open(tester, FakeBluetooth([hw]), api: api);
    await findAndPair(tester);
    expect(find.textContaining("The code didn't match"), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await run(tester);
    expect(hw.pairings, 2);
    expect(find.text('Which Wi-Fi should the frame use?'), findsOneWidget);
  });

  testWidgets('a wrong Wi-Fi password goes back to Wi-Fi with the reason', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api);
    await open(tester, FakeBluetooth([hw]), api: api);
    await findAndPair(tester);
    await joinWifi(tester, 'Home', 'battery staple');
    expect(find.text("Couldn't join Home: the password didn't work."), findsOneWidget);
    expect(find.text('Which Wi-Fi should the frame use?'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Wi-Fi password'), 'correct horse');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await run(tester);
    expect(find.text('Kitchen is connected'), findsOneWidget);
    expect(hw.provisions, hasLength(2));
  });

  testWidgets('an open network, and one the frame cannot see', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api);
    await open(tester, FakeBluetooth([hw]), api: api);
    await findAndPair(tester);
    await tester.tap(find.text('Other network…'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Network name'), 'Upstairs');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await run(tester);
    expect(find.textContaining("The frame couldn't find Upstairs"), findsOneWidget);

    await tester.tap(find.text('Cafe'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Wi-Fi password'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await run(tester);
    expect(find.text('Kitchen is connected'), findsOneWidget);
    expect(hw.provisions.last.password, '');
  });

  testWidgets('an expired pairing token is replaced without asking', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api, expired: {'T1'.padRight(26, '0')});
    await open(tester, FakeBluetooth([hw]), api: api);
    await findAndPair(tester);
    await joinWifi(tester, 'Home', 'correct horse');
    expect(api.tokens, hasLength(2));
    expect(hw.provisions.map((p) => p.pairingToken), api.tokens);
    expect(find.text('Kitchen is connected'), findsOneWidget);
  });

  testWidgets('a different model: switch the frame (photos go), then carry on', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api, modelId: 'pimoroni-7-3');
    await open(tester, FakeBluetooth([hw]), api: api);
    await findAndPair(tester);
    expect(find.text('This frame is a Pimoroni Inky 7.3", but Kitchen is set up for a reTerminal E1002 7.3".'), findsOneWidget);
    expect(find.textContaining('All 48 photos will be removed'), findsOneWidget);

    await tester.tap(find.text('Switch'));
    await run(tester);
    expect(api.calls, contains('model pimoroni-7-3'));
    expect(find.text('Which Wi-Fi should the frame use?'), findsOneWidget);
    await joinWifi(tester, 'Home', 'correct horse');
    expect(find.text('Kitchen is connected'), findsOneWidget);
  });

  testWidgets('hardware still linked to another frame', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final hw = hardware(api, frameId: 'someone-elses');
    await open(tester, FakeBluetooth([hw]), api: api);
    await findAndPair(tester);
    expect(find.textContaining('still linked to another Ink Frame'), findsOneWidget);
    expect(find.text('Start again'), findsOneWidget);
    expect(hw.connected, isFalse);
  });

  testWidgets('the same hardware again (say, new Wi-Fi) is fine', (tester) async {
    final api = FakeFrameApi(frame: frameJson(), members: [priya]);
    final hw = hardware(api, frameId: 'f');
    await open(tester, FakeBluetooth([hw]), api: api);
    expect(find.textContaining('stops showing photos once this one is connected'), findsOneWidget);
    await findAndPair(tester);
    expect(find.text('Which Wi-Fi should the frame use?'), findsOneWidget);
  });

  testWidgets('several frames: pick the one whose name is on its screen', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    final a = FakeHardware(suffix: '1A2B'), b = FakeHardware(suffix: '9F00');
    await open(tester, FakeBluetooth([b, a]), api: api);
    await findAndPair(tester);
    expect(find.text('Which frame?'), findsOneWidget);
    expect(find.text('InkFrame-1A2B'), findsOneWidget);
    await tester.tap(find.text('InkFrame-9F00'));
    await run(tester);
    expect((a.pairings, b.pairings), (0, 1));
  });

  testWidgets('Bluetooth off, permission refused, nothing found', (tester) async {
    final bt = FakeBluetooth()..radio = BluetoothState.off;
    await open(tester, bt);
    await tester.tap(find.text('Find the frame'));
    await run(tester);
    expect(find.text('Turn on Bluetooth on this device, then try again.'), findsOneWidget);

    bt
      ..radio = BluetoothState.on
      ..allowed = false;
    await tester.tap(find.text('Try again'));
    await run(tester);
    expect(find.textContaining('needs permission to use Bluetooth'), findsOneWidget);

    bt
      ..allowed = true
      ..frames.clear();
    await tester.tap(find.text('Try again'));
    await run(tester, ConnectFrame.findLimit + const Duration(seconds: 1));
    expect(find.text("Couldn't find the frame."), findsOneWidget);
    expect(find.textContaining('hold its green button for 3 seconds', findRichText: true), findsNothing);
    expect(find.text('No code? Hold its green button for 3 seconds.'), findsOneWidget);
  });

  testWidgets('developer: connect frame_sim with a code', (tester) async {
    final api = FakeFrameApi(frame: frameJson(connected: false), members: [priya]);
    await open(tester, FakeBluetooth(), api: api, devMode: true);
    await tester.tap(find.text('Connect with a code (developer)'));
    await run(tester);
    final command = DevConnectScreen.command(kitchen, api.tokens.single);
    expect(command, 'dart run bin/frame_sim.dart claim --ref aaaaaaaaaaaaaaaaaaaa --token ${api.tokens.single}');
    expect(find.text(command), findsOneWidget);
    expect(find.text('Waiting for the frame…'), findsOneWidget);

    api.claimed('sim-0001');
    await run(tester, const Duration(seconds: 4));
    expect(find.text('Kitchen is connected'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
