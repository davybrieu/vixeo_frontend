import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'media_kit_player_engine.dart';
import 'native_player_engine.dart';
import 'player_engine.dart';
import 'video_player_engine.dart';

/// Android (phones, tablets, Android TV) and iOS: the native player. Windows: media_kit. The tests
/// (which run on the computer) and any other platform: `video_player`.
PlayerEngine createPlatformEngine(PlayerSource source) {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) return NativePlayerEngine();
  if (!kIsWeb && Platform.isWindows) return MediaKitPlayerEngine();
  return VideoPlayerEngine();
}
