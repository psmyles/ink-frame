// Storage (app-flow §5.3) and the Frame screen's "getting full" notice.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/features/storage/storage_screen.dart';

import 'fake_frame_api.dart';
import 'frame_screen_test.dart' as fs;
import 'frame_screen_test.dart' show alice, kitchen, priya;

void main() {
  testWidgets('the owner sees the total and everyone', (tester) async {
    await pumpFrameScreen(
      tester,
      () => const StorageScreen(address: kitchen),
      address: kitchen,
      me: priya,
      owner: priya,
      api: FakeFrameApi(
        members: [priya, alice],
        usage: sampleUsage(users: [
          const UsageEntry(images: 40, bytes: 300 * 1024 * 1024, userId: 'priya'),
          const UsageEntry(images: 8, bytes: 12 * 1024 * 1024, userId: 'alice'),
        ]),
      ),
    );
    expect(find.text('312 MB of 1 GB'), findsOneWidget);
    expect(find.text('48 photos · Free Supabase plan'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('40 photos · 300 MB'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('8 photos · 12 MB'), findsOneWidget);
    expect(find.text("The frame's own downloads aren't counted here."), findsOneWidget);
  });

  testWidgets('the Frame screen says when storage is getting full', (tester) async {
    await fs.pump(tester, me: alice, storage: sampleUsage(bytes: (0.85 * gb).round()));
    expect(find.text("Kitchen's storage is getting full (85 %)."), findsOneWidget);
    expect(find.text('See storage'), findsOneWidget);
  });

  testWidgets('and when it is full', (tester) async {
    await fs.pump(tester, me: alice, storage: Usage(
      frame: const UsageEntry(images: 900, bytes: 950 * 1024 * 1024, maxBytes: 950 * 1024 * 1024),
      freeTierBytes: gb,
      users: const [],
    ));
    expect(find.text("Kitchen's storage is full. Delete some photos to add more."), findsOneWidget);
  });

  testWidgets('no notice with room to spare', (tester) async {
    await fs.pump(tester, me: alice);
    expect(find.textContaining('storage'), findsNothing);
  });
}
