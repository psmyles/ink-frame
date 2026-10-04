// Incoming links (app-flow §5.1): an invite opens Join; an address no screen has
// lands on Welcome/Home instead of an error page.
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/app.dart';
import 'package:ink_frame/data/frame_link.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/join/join_screen.dart';
import 'package:ink_frame/routing/router.dart';
import 'package:ink_frame/state/providers.dart';

import 'layout_test.dart' show kitchen;

class FakeLinks implements AppLinks {
  final controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get uriLinkStream => controller.stream;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<FakeLinks> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final links = FakeLinks();
  addTearDown(links.controller.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [storeProvider.overrideWithValue(MemoryStore())],
    retry: (_, _) => null,
    child: InkFrameApp(appLinks: links),
  ));
  await tester.pumpAndSettle();
  return links;
}

void main() {
  testWidgets('an invite link opens Join with the link filled in', (tester) async {
    final links = await pump(tester);
    expect(find.text('Continue with Google'), findsOneWidget);
    final invite = FrameLink([kitchen], 'ABCDE-FGHJK');
    links.controller.add(Uri.parse('inkframe://join?${invite.toHttps().split('#').last}'));
    await tester.pumpAndSettle();
    final join = tester.widget<JoinScreen>(find.byType(JoinScreen));
    expect(FrameLink.parse(join.initialLink!)!.code, 'ABCDE-FGHJK');
  });

  testWidgets('an unknown address goes to Welcome, not an error page', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(InkFrameApp)));
    container.read(routerProvider).go('/?u=https://x.supabase.co&k=sb_publishable_x');
    await tester.pumpAndSettle();
    expect(find.textContaining('Page Not Found', findRichText: true), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
