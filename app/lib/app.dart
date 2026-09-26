import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/frame_link.dart';
import 'l10n/app_localizations.dart';
import 'routing/router.dart';
import 'theme/theme.dart';

class InkFrameApp extends ConsumerStatefulWidget {
  const InkFrameApp({super.key, this.appLinks});

  /// Null in tests.
  final AppLinks? appLinks;

  @override
  ConsumerState<InkFrameApp> createState() => _InkFrameAppState();
}

class _InkFrameAppState extends ConsumerState<InkFrameApp> {
  StreamSubscription<Uri>? _links;

  @override
  void initState() {
    super.initState();
    // inkframe://join?… (from the /join page or a QR code) opens Join.
    _links = widget.appLinks?.uriLinkStream.listen((uri) {
      if (FrameLink.parse(uri.toString()) == null) return;
      ref.read(routerProvider).push(Uri(path: '/join', queryParameters: {'link': uri.toString()}).toString());
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: InkTheme.light(),
        darkTheme: InkTheme.dark(),
        routerConfig: ref.watch(routerProvider),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
      );
}
