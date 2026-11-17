import 'dart:io' show Platform;

import 'native_player_engine.dart';
import 'player_engine.dart';
import 'video_player_engine.dart';

/// Android (phones, tablets, Android TV) and iOS: the native player. Desktop and the tests
/// (which run on the computer, whatever platform they pretend to be): `video_player`.
PlayerEngine createPlatformEngine(PlayerSource source) =>
    Platform.isAndroid || Platform.isIOS ? NativePlayerEngine() : VideoPlayerEngine();
