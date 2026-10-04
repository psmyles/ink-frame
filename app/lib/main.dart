import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'battery/background.dart';
import 'state/photos.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  // lib/imaging/zopfli.dart follows Zopfli's design and code structure.
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['zopfli'], 'Zopfli: Copyright 2011 Google Inc. Licensed under the Apache License, '
        'Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0). The Dart deflate encoder in Ink Frame is a port of its method.');
  });
  // The low-battery check (phones); a failure here must never stop the app starting.
  scheduleBatteryChecks().catchError((Object e) => debugPrint('battery checks not scheduled: $e'));
  runApp(ProviderScope(
    // Errors are shown where they happen (asleep, offline, …); no silent retries.
    retry: (_, _) => null,
    overrides: [cacheRootProvider.overrideWithValue(support)],
    child: InkFrameApp(appLinks: AppLinks()),
  ));
}
