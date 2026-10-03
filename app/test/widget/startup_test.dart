// Starting the app: while this device's frames are read (secure storage can take a
// moment) it says so, and nothing that looks like signing in shows up first. A
// frame's card shows its name and "Loading…" while it's being read.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/app.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/state/providers.dart';

import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show alice, kitchen, priya;

/// Secure storage that takes a moment to answer.
class SlowStore extends MemoryStore {
  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return super.read(key);
  }
}

Future<void> start(WidgetTester tester, MemoryStore store, {Future<FrameView>? view}) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      storeProvider.overrideWithValue(store),
      frameViewProvider(kitchen).overrideWith((ref) => view ?? Future.value(FakeFrameApi().view(alice, priya))),
    ],
    child: const InkFrameApp(),
  ));
}

/// This device knows Kitchen (and its name from last time).
Future<Map<String, String>> kitchenOnDevice() async {
  final seed = MemoryStore();
  await FramesRepository(seed).add(kitchen);
  seed.values['cache:${kitchen.ref}'] = jsonEncode({'name': 'Kitchen', 'owner_name': 'Priya', 'is_mine': false});
  return seed.values;
}

void main() {
  testWidgets('signed in: "Loading your frames…", never "no frames" or sign-in buttons', (tester) async {
    await start(tester, SlowStore()..values.addAll(await kitchenOnDevice()));
    expect(find.text('No frames yet'), findsNothing);
    expect(find.text("I've been invited"), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Loading your frames…'), findsOneWidget);
    expect(find.text("I've been invited"), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Loading your frames…'), findsNothing);
    await tester.pump(const Duration(seconds: 2)); // the slow store's last reads
  });

  testWidgets('a quick start shows no spinner at all', (tester) async {
    await start(tester, MemoryStore()..values.addAll(await kitchenOnDevice()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Loading your frames…'), findsNothing);
  });

  testWidgets('no frames on this device: Welcome', (tester) async {
    await start(tester, SlowStore());
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("I've been invited"), findsOneWidget);
  });

  testWidgets("a frame's card: its name and Loading… until it's read", (tester) async {
    final view = Completer<FrameView>();
    await start(tester, MemoryStore()..values.addAll(await kitchenOnDevice()), view: view.future);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Kitchen'), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);

    view.complete(FakeFrameApi().view(alice, priya));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Loading…'), findsNothing);
    expect(find.text('Set up by Priya'), findsOneWidget);
  });
}
