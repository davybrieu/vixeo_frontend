import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'player_engine.dart';
import 'player_errors.dart';
import 'web/browser_support.dart';

/// The official `video_player` plugin. On the web its implementation (`video_player_web`) is the
/// browser's own HTML5 `<video>`: MP4 everywhere, HLS where the browser plays it itself (Safari).
/// It is also the engine of the platforms without a native one (desktop) and of the tests.
///
/// It never runs on Android / iOS (see `engine_factory_io.dart`).
class VideoPlayerEngine extends PlayerEngine {
  VideoPlayerController? _controller;
  PlayerSource? _source;
  double _volume = 1;

  /// Web: the browser refused a start, and the stream was opened again, paused. Once only.
  bool _recovered = false;

  @override
  String get name => kIsWeb ? 'html5' : 'video_player';

  @override
  Future<void> open(PlayerSource source) async {
    if (kIsWeb && source.drm != null) {
      // No EME adapter yet (docs/lecteur.md): say so instead of showing a black picture.
      throw const PlayerError(PlayerErrorKind.drm, 'DRM is not implemented on the web');
    }
    _source = source;
    final controller = _create(source);
    try {
      await controller.initialize();
    } catch (e) {
      final detail = _describe(e);
      throw PlayerError(classifyPlayerError(detail), detail);
    }
    _sync();
  }

  VideoPlayerController _create(PlayerSource source) {
    final controller = VideoPlayerController.networkUrl(Uri.parse(source.url), httpHeaders: source.headers);
    _controller = controller;
    controller.addListener(_sync);
    return controller;
  }

  static String _describe(Object error) =>
      error is PlatformException ? '${error.code}: ${error.message ?? ''}' : '$error';

  /// Copies the plugin's state into ours.
  void _sync() {
    final controller = _controller;
    if (controller == null || isDisposed) return;
    final v = controller.value;
    if (v.hasError) {
      if (value.hasError) return;
      final detail = v.errorDescription ?? '';
      if (kIsWeb && !_recovered && looksLikeAutoplayRefusal(detail)) {
        unawaited(_recoverFromAutoplayRefusal());
        return;
      }
      value = value.copyWith(error: PlayerError(classifyPlayerError(detail), detail), playing: false, buffering: false);
      return;
    }
    value = value.copyWith(
      initialized: v.isInitialized,
      playing: v.isPlaying,
      buffering: v.isBuffering,
      position: v.position,
      duration: v.duration,
    );
  }

  /// Web: a start the browser refuses (autoplay policy) leaves `video_player` in an error state
  /// it never leaves, although nothing is wrong with the stream. The stream is opened again and
  /// stays paused: the play sign shows, and a tap (a gesture the browser sees) starts it.
  Future<void> _recoverFromAutoplayRefusal() async {
    final source = _source;
    final refused = _controller;
    if (source == null || refused == null) return;
    _recovered = true;
    refused.removeListener(_sync);
    value = value.copyWith(initialized: false, playing: false, buffering: false);
    // Not during its own notification (ChangeNotifier forbids it): right after.
    unawaited(Future.microtask(refused.dispose));

    final controller = _create(source);
    try {
      await controller.initialize();
      if (isDisposed || controller != _controller) return;
      await controller.setVolume(_volume);
    } catch (e) {
      final detail = _describe(e);
      value = value.copyWith(error: PlayerError(classifyPlayerError(detail), detail));
      return;
    }
    _sync();
  }

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller == null || isDisposed) return;
    if (kIsWeb && _volume > 0 && !viewerHasInteracted()) {
      // Nobody touched the page yet (a link opened straight on the player): the browser only
      // lets a muted video start. The sound button then says « Activer le son ».
      await controller.setVolume(0);
      value = value.copyWith(autoplayMuted: true);
    }
    await controller.play();
  }

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seekTo(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    if (volume > 0 && value.autoplayMuted) value = value.copyWith(autoplayMuted: false);
    await _controller?.setVolume(volume);
  }

  @override
  Future<Duration?> get position async {
    final controller = _controller;
    if (controller == null || isDisposed || !controller.value.isInitialized) return null;
    return controller.position;
  }

  @override
  Widget buildView(BuildContext context) => ValueListenableBuilder<PlayerEngineValue>(
    valueListenable: this,
    builder: (context, value, _) {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return const SizedBox.expand();
      return Center(
        child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller)),
      );
    },
  );

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_sync);
    // Not during a notification of the controller (ChangeNotifier forbids it): right after.
    if (controller != null) unawaited(Future.microtask(controller.dispose));
    super.dispose();
  }
}
