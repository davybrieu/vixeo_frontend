import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/device/layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: clean URLs (/accueil rather than /#/accueil). The web server must
  // serve index.html for unknown paths (see README).
  usePathUrlStrategy();
  await DeviceInfo.init();

  runApp(
    ProviderScope(
      // Errors are shown with a "Réessayer" button instead of silent retries.
      retry: (_, _) => null,
      child: const VixeoApp(),
    ),
  );
}
