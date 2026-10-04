// Desktop: Ctrl/Cmd+V anywhere on Welcome pastes an invite link (app-flow §2.3).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ink_frame/data/secure_store.dart';
import 'package:ink_frame/features/welcome/welcome_screen.dart';
import 'package:ink_frame/l10n/app_localizations.dart';
import 'package:ink_frame/state/providers.dart';
import 'package:ink_frame/theme/theme.dart';

Future<void> pasteOnWelcome(WidgetTester tester, String clipboard) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') return {'text': clipboard};
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const WelcomeScreen()),
    GoRoute(path: '/join', builder: (_, s) => Scaffold(body: Text('Join ${s.uri.queryParameters['link']}'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [storeProvider.overrideWithValue(MemoryStore())],
    child: MaterialApp.router(
      theme: InkTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  const link = 'https://psmyles.github.io/ink-frame/join#u=https%3A%2F%2Faaaaaaaaaaaaaaaaaaaa.supabase.co&k=sb_publishable_AbCdEf0123456789&c=ABCDE-FGHJK';

  testWidgets('an invite link on the clipboard opens Join with it', (tester) async {
    await pasteOnWelcome(tester, link);
    expect(find.text('Join $link'), findsOneWidget);
  });

  testWidgets('anything else is ignored', (tester) async {
    await pasteOnWelcome(tester, 'hello');
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
