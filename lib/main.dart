import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/device/layout.dart';
import 'core/licenses.dart';
import 'core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) await _setUpWindows();

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

/// Windows: the video engine (media_kit, `features/playback/engine`) and the window: its title, a
/// size that fits the 1280 × 720 layout, and the smallest it may get.
Future<void> _setUpWindows() async {
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'Vixeo',
      size: Size(1280, 800),
      minimumSize: Size(960, 600),
      center: true,
      backgroundColor: VxColors.background,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
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
