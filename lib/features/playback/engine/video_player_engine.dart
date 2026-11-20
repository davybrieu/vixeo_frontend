import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'player_engine.dart';
import 'player_errors.dart';

/// The official `video_player` plugin: the engine of the tests (which run on the computer) and of
/// the platforms without an engine of their own (macOS, Linux).
///
/// It never runs on Android / iOS (native engine) nor on Windows (media_kit), see
/// `engine_factory_io.dart`.
class VideoPlayerEngine extends PlayerEngine {
  VideoPlayerController? _controller;

  @override
  String get name => 'video_player';

  @override
  Future<void> open(PlayerSource source) async {
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
      value = value.copyWith(error: PlayerError(classifyPlayerError(detail), detail), playing: false, buffering: false);
      return;
    }
    value = value.copyWith(
      initialized: v.isInitialized,
      playing: v.isPlaying,
      buffering: v.isBuffering,
      position: v.position,
      duration: v.duration,
      aspectRatio: v.size.width > 0 && v.size.height > 0 ? v.size.width / v.size.height : null,
    );
  }

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller == null || isDisposed) return;
    await controller.play();
  }

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seekTo(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setVolume(double volume) async {
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
