import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

bool _fullscreen = false;
bool _landscapeLocked = false;

/// Whether the player is shown full screen.
bool isFullscreen() => _fullscreen;

/// The player is always horizontal (demande du développeur): from its opening to its closing,
/// whatever the full screen. Android TV is landscape anyway.
Future<void> lockLandscape() async {
  _landscapeLocked = true;
  await _applyOrientation();
}

/// Gives the orientation back to the system (and to the rest of the app) when the player closes.
Future<void> unlockOrientation() async {
  _landscapeLocked = false;
  await _applyOrientation();
}

Future<void> enterFullscreen() async {
  _fullscreen = true;
  if (kIsWeb) return;
  // Windows: the window covers the whole screen (taskbar included), as in a desktop player.
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.setFullScreen(true);
    return;
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await _applyOrientation();
}

Future<void> exitFullscreen() async {
  if (!_fullscreen) return;
  _fullscreen = false;
  if (Platform.isWindows) {
    await windowManager.setFullScreen(false);
    return;
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await _applyOrientation();
}

/// Landscape while the player is open or full screen; otherwise every orientation (the app's
/// default: none is set anywhere else).
Future<void> _applyOrientation() async {
  // A browser has no native orientation lock here; a computer's screen has none either.
  if (kIsWeb || Platform.isWindows) return;
  await _setOrientation();
}

Future<void> _setOrientation() => SystemChrome.setPreferredOrientations(
  _landscapeLocked || _fullscreen
      ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
      : const <DeviceOrientation>[],
);
