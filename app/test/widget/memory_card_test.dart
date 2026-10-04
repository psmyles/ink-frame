// The frame's memory card as it last reported it (openapi.yaml 2.2.0): the room for
// photos, and "No memory card" on the frame's card on Home.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_frame/data/models.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';
import 'package:ink_frame/widgets/status_line.dart';

import 'fake_frame_api.dart';
import 'frame_screen_test.dart' show priya;

const mb = 1024 * 1024;

Frame frame(Map<String, int?> card, {bool connected = true}) => Frame.fromJson(frameJson(card: card, connected: connected));

void main() {
  test('room for photos: free space plus what they take, less the 8 MB kept free', () {
    final f = frame({'sd_total_bytes': 256 * mb, 'sd_free_bytes': 100 * mb, 'cache_bytes': 50 * mb});
    expect(f.photoRoomBytes, 142 * mb);
    expect(f.cardShortBy(142 * mb), 0);
    expect(f.cardShortBy(150 * mb), 8 * mb);
  });

  test('unknown without a report, none without a card, nothing while not connected', () {
    expect(frame({}).photoRoomBytes, isNull);
    expect(frame({}).cardShortBy(999 * mb), 0);
    expect(frame({'sd_total_bytes': 0}).noCard, isTrue);
    expect(frame({'sd_total_bytes': 0}).photoRoomBytes, isNull);
    expect(frame({'sd_total_bytes': 0}, connected: false).noCard, isFalse);
  });

  testWidgets('the Home card says when there is no memory card', (tester) async {
    final summary = FakeFrameApi(frame: frameJson(card: {'sd_total_bytes': 0})).view(priya, priya).summary!;
    await tester.pumpWidget(MaterialApp(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: StatusLine(FrameView(summary: summary))),
    ));
    expect(find.text('No memory card'), findsOneWidget);
  });
}
