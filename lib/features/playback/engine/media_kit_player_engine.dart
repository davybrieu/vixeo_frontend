import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'player_engine.dart';
import 'player_errors.dart';

/// Windows: media_kit (libmpv, bundled by `media_kit_libs_windows_video`). It plays what the
/// plug-ins find (HLS, MP4, MKV…) and sends the headers they ask for (Referer, User-Agent…).
///
/// `MediaKit.ensureInitialized()` is called once at launch (`main.dart`), on Windows only.
class MediaKitPlayerEngine extends PlayerEngine {
  Player? _player;
  VideoController? _video;
  int _width = 0;
  int _height = 0;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// How long a stream may take to show its first picture (or its length) before it is given up.
  static const openTimeout = Duration(seconds: 30);

  @override
  String get name => 'media_kit';

  @override
  Future<void> open(PlayerSource source) async {
    final player = Player();
    _player = player;
    _video = VideoController(player);
    notifyListeners(); // the view can show the video's texture

    final opened = Completer<void>();
    void ready() {
      if (!opened.isCompleted) opened.complete();
    }

    _subscriptions.addAll([
      player.stream.error.listen((message) {
        final error = PlayerError(classifyPlayerError(message), message);
        if (!opened.isCompleted) {
          opened.completeError(error);
        } else {
          value = value.copyWith(error: error, playing: false, buffering: false);
        }
      }),
      player.stream.playing.listen((playing) => value = value.copyWith(playing: playing)),
      player.stream.buffering.listen((buffering) => value = value.copyWith(buffering: buffering)),
      player.stream.position.listen((position) => value = value.copyWith(position: position)),
      player.stream.duration.listen((duration) {
        value = value.copyWith(duration: duration);
        if (duration > Duration.zero) ready();
      }),
      player.stream.width.listen((width) {
        _width = width ?? 0;
        _size();
      }),
      player.stream.height.listen((height) {
        _height = height ?? 0;
        _size();
        if (_height > 0) ready();
      }),
    ]);

    await player.open(Media(source.url, httpHeaders: source.headers), play: false);
    try {
      await opened.future.timeout(openTimeout);
    } on TimeoutException {
      throw const PlayerError(PlayerErrorKind.network, 'media_kit: no picture after 30 s');
    }
    if (isDisposed) return;
    value = value.copyWith(initialized: true);
  }

  /// The picture's shape, once mpv knows it.
  void _size() {
    if (_width > 0 && _height > 0) value = value.copyWith(aspectRatio: _width / _height);
  }

  @override
  Future<void> play() async => _player?.play();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> seekTo(Duration position) async => _player?.seek(position);

  /// media_kit's volume goes from 0 to 100.
  @override
  Future<void> setVolume(double volume) async {
    if (volume > 0 && value.autoplayMuted) value = value.copyWith(autoplayMuted: false);
    await _player?.setVolume((volume.clamp(0, 1) * 100).toDouble());
  }

  @override
  Future<Duration?> get position async {
    final player = _player;
    if (player == null || isDisposed) return null;
    return player.state.position;
  }

  @override
  Widget buildView(BuildContext context) => ListenableBuilder(
    listenable: this,
    builder: (context, _) {
      final video = _video;
      if (video == null) return const SizedBox.expand();
      // The player's own controls are not wanted: PlayerScreen draws them, the same everywhere.
      return Video(controller: video, controls: NoVideoControls, fill: Colors.black);
    },
  );

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    _video = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}
