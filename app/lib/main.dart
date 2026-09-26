import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    // Errors are shown where they happen (asleep, offline, …); no silent retries.
    retry: (_, _) => null,
    child: InkFrameApp(appLinks: AppLinks()),
  ));
}
