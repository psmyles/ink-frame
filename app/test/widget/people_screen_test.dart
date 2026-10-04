// People and invites (app-flow §5.1–5.2).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/frame_directory.dart';
import 'package:ink_frame/data/frames_repository.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/people/people_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../unit/fake_directory.dart';
import '../unit/frame_directory_test.dart' show google;
import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show alice, kitchen, priya;

const bob = Member(userId: 'bob', role: Role.member, displayName: 'Bob');

Future<FakeFrameApi> open(WidgetTester tester,
        {required Member me, List<Member>? members, List<Invite>? invites, MemoryStore? store, FrameDirectory? directory}) =>
    pumpFrameScreen(
      tester,
      () => const PeopleScreen(address: kitchen),
      address: kitchen,
      me: me,
      owner: priya,
      api: FakeFrameApi(members: members ?? [priya, alice, bob], invites: invites),
      store: store,
      directory: directory,
    );

void main() {
  testWidgets('the owner sees everyone, with Owner and You, and can remove others', (tester) async {
    final api = await open(tester, me: priya);
    expect(find.text('Invite someone'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Remove'), findsNWidgets(2)); // not on the owner
    expect(find.text('Leave this album'), findsNothing);

    await tester.tap(find.text('Remove').first);
    await tester.pumpAndSettle();
    expect(find.text('Remove Alice from Kitchen? Their photos stay; you can delete them.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(api.calls, ['remove alice']);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('just the owner: "Just you so far"', (tester) async {
    await open(tester, me: priya, members: [priya]);
    expect(find.text('Just you so far'), findsOneWidget);
  });

  testWidgets('active invites can be cancelled', (tester) async {
    final api = await open(tester, me: priya, invites: [
      Invite(id: 'i1', expiresAt: DateTime(2026, 10, 10), maxUses: 1, uses: 0),
      Invite(id: 'i2', expiresAt: DateTime(2026, 10, 30), maxUses: 10, uses: 3),
    ]);
    expect(find.text('For 1 person · expires Oct 10'), findsOneWidget);
    expect(find.text('3 of 10 joined · expires Oct 30'), findsOneWidget);
    await tester.tap(find.text('Cancel invite').first);
    await tester.pumpAndSettle();
    expect(api.calls, ['revoke i1']);
    expect(find.text('For 1 person · expires Oct 10'), findsNothing);
  });

  testWidgets('the invite sheet makes an invite with a QR code and its code', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    final api = await open(tester, me: priya);
    await tester.tap(find.text('Invite someone'));
    await tester.pumpAndSettle();
    expect(api.calls, ['invite 1 7d']);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ABCDE-FGHJ1'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);

    await tester.tap(find.text('Copy code'));
    await tester.pumpAndSettle();
    expect(copied, 'ABCDE-FGHJ1');
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, startsWith('https://psmyles.github.io/ink-frame/join#u='));
    expect(copied, endsWith('&c=ABCDE-FGHJ1'));

    // A different option makes a new invite and revokes the one shown before.
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Up to 10 people'));
    await tester.pumpAndSettle();
    expect(api.calls, ['invite 1 7d', 'invite 10 7d', 'revoke inv1']);
    expect(find.text('ABCDE-FGHJ2'), findsOneWidget);
  });

  testWidgets('anyone else can leave; the frame goes from this device and your list', (tester) async {
    final store = MemoryStore();
    final server = FakeDirectoryServer()..accounts['alice'] = [kitchen];
    final directory = server.directory(store);
    await directory.signIn(google('alice'));
    final api = await open(tester, me: alice, store: store, directory: directory);
    expect(find.text('Invite someone'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    await tester.tap(find.text('Leave this album'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Leave Kitchen? You'll stop seeing its photos."), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(api.calls, ['remove alice']);
    expect(await FramesRepository(store).load(), isEmpty);
    expect(find.text('Home'), findsOneWidget);
    expect(server.accounts['alice'], isEmpty);
  });
}
