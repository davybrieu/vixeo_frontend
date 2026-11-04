import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/device/layout.dart';
import 'core/licenses.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: clean URLs (/accueil rather than /#/accueil). The web server must
  // serve index.html for unknown paths (see README).
  usePathUrlStrategy();

  // A release build without an https:// API stops here instead of sending data in clear text.
  final configError = AppConfig.configurationError;
  if (configError != null) {
    runApp(ConfigurationErrorApp(message: configError));
    return;
  }

  registerBundledLicenses();
  await DeviceInfo.init();

  runApp(
    ProviderScope(
      // Errors are shown with a "Réessayer" button instead of silent retries.
      retry: (_, _) => null,
      child: const VixeoApp(),
    ),
  );
}

/// Shown instead of the app when the build is misconfigured (see [AppConfig.configurationError]).
class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildVixeoTheme(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: VxText.body(16, color: VxColors.textSoft),
          ),
        ),
      ),
    ),
  );
}
