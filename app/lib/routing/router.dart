import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/frame_link.dart';
import '../features/account/account_screen.dart';
import '../features/frame/frame_screen.dart';
import '../features/home/home_screen.dart';
import '../features/join/join_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/welcome/welcome_screen.dart';
import '../state/providers.dart';
import '../widgets/adaptive_shell.dart';

/// Routes (app-flow §2.1). Home, a frame and Account share the two-pane shell.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(framesProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  FrameAddress? byRef(String r) {
    for (final f in ref.read(framesProvider).value ?? const <FrameAddress>[]) {
      if (f.ref == r) return f;
    }
    return null;
  }

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    // An address no screen has (e.g. a stray link): go Home (or Welcome) rather
    // than show an error page. Invite links are handled in app.dart.
    onException: (context, state, router) => router.go('/home'),
    redirect: (context, state) {
      final frames = ref.read(framesProvider);
      if (frames.isLoading) return null;
      final none = (frames.value ?? []).isEmpty;
      final path = state.uri.path;
      if (none && (path == '/home' || path.startsWith('/frame/'))) return '/welcome';
      if (!none && path == '/welcome') return '/home';
      if (path.startsWith('/frame/') && byRef(state.pathParameters['ref'] ?? '') == null) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: '/join',
        builder: (_, state) => JoinScreen(
          initialLink: state.uri.queryParameters['link'],
          returning: state.uri.queryParameters['mode'] == 'signin',
        ),
      ),
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      ShellRoute(
        builder: (context, state, child) => AdaptiveShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', pageBuilder: (_, _) => const NoTransitionPage(child: HomeScreen())),
          GoRoute(
            path: '/frame/:ref',
            pageBuilder: (_, state) {
              final address = byRef(state.pathParameters['ref']!)!;
              return NoTransitionPage(
                key: ValueKey(address.ref),
                child: FrameScreen(address: address, showTip: state.uri.queryParameters['tip'] == '1'),
              );
            },
          ),
          GoRoute(path: '/account', pageBuilder: (_, _) => const NoTransitionPage(child: AccountScreen())),
        ],
      ),
    ],
  );
});
