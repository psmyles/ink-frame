import 'dart:async';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/frame_link.dart';
import 'l10n/app_localizations.dart';
import 'routing/router.dart';
import 'state/providers.dart';
import 'theme/theme.dart';
import 'widgets/choose_album_dialog.dart';

class InkFrameApp extends ConsumerStatefulWidget {
  const InkFrameApp({super.key, this.appLinks});

  /// Null in tests.
  final AppLinks? appLinks;

  @override
  ConsumerState<InkFrameApp> createState() => _InkFrameAppState();
}

class _InkFrameAppState extends ConsumerState<InkFrameApp> {
  StreamSubscription<Uri>? _links;
  StreamSubscription<void>? _shares;
  AppLifecycleListener? _lifecycle;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  var _receiving = false, _again = false;

  @override
  void initState() {
    super.initState();
    _links = widget.appLinks?.uriLinkStream.listen((uri) {
      // inkframe://share: the iOS share extension has left photos in the inbox.
      if (uri.scheme == 'inkframe' && uri.host == 'share') return unawaited(_receiveShared());
      // inkframe://join?… (from the /join page or a QR code) opens Join.
      if (FrameLink.parse(uri.toString()) == null) return;
      ref.read(routerProvider).push(Uri(path: '/join', queryParameters: {'link': uri.toString()}).toString());
    }, onError: (_) {});
    final inbox = ref.read(sharedInboxProvider);
    if (inbox != null) {
      _shares = inbox.changes.listen((_) => _receiveShared());
      // Also when the app comes back: a share the extension couldn't open the app for.
      _lifecycle = AppLifecycleListener(onResume: _receiveShared);
      unawaited(_receiveShared());
    }
  }

  @override
  void dispose() {
    _links?.cancel();
    _shares?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Photos shared from another app go to an album's Prepare: the only album, or
  /// the one the person picks.
  Future<void> _receiveShared() async {
    final inbox = ref.read(sharedInboxProvider);
    if (inbox == null) return;
    if (_receiving) {
      _again = true;
      return;
    }
    _receiving = true;
    try {
      do {
        _again = false;
        final photos = await inbox.take();
        if (photos.isNotEmpty) await _sendShared(photos);
      } while (_again && mounted);
    } catch (e) {
      debugPrint('shared photos: $e');
    } finally {
      _receiving = false;
    }
  }

  Future<void> _sendShared(List<(String, Uint8List)> photos) async {
    final albums = await ref.read(framesProvider.future);
    await WidgetsBinding.instance.endOfFrame; // the router's first screen is up
    final router = ref.read(routerProvider);
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (!mounted || context == null || !context.mounted) return;
    if (albums.isEmpty) {
      _messenger.currentState?.showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).shareNeedsAlbum)));
      return;
    }
    final album = albums.length == 1 ? albums.single : await chooseAlbumFor(context, albums);
    if (album == null) return;
    ref.read(incomingPhotosProvider.notifier).send(IncomingPhotos(album.ref, photos));
    router.go('/frame/${album.ref}');
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        scaffoldMessengerKey: _messenger,
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
