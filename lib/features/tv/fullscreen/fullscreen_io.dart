import 'package:flutter/services.dart';

bool _fullscreen = false;

/// Whether the player is shown full screen.
bool isFullscreen() => _fullscreen;

Future<void> enterFullscreen() async {
  _fullscreen = true;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
}

Future<void> exitFullscreen() async {
  if (!_fullscreen) return;
  _fullscreen = false;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations(const []);
}
