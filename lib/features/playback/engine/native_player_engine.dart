import 'dart:async';

import 'package:better_native_video_player/better_native_video_player.dart'
    show
        NativeVideoPlayer,
        NativeVideoPlayerController,
        PlayerActivityEvent,
        PlayerActivityState,
        PlayerControlEvent,
        PlayerControlState;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import 'player_engine.dart';
import 'player_errors.dart';

/// Android and iOS: the platform's own player (ExoPlayer / AVPlayer) through
/// `better_native_video_player`. The plugin draws the picture in a native view; its own controls
/// are off, the Flutter ones of `PlayerScreen` are drawn over it.
///
/// This file is only ever imported by `engine_factory_io.dart`: the web build never sees the
/// plugin (it has no web implementation), and no native API is called in a browser.
class NativePlayerEngine extends PlayerEngine {
  NativePlayerEngine()
    : _controller = NativeVideoPlayerController(
        id: _nextId++,
        autoPlay: false,
        // One set of controls on every platform: ours.
        showNativeControls: false,
        allowsPictureInPicture: false,
        canStartPictureInPictureAutomatically: false,
        // Orientation and full screen are the screen's business (features/tv/fullscreen).
        lockToLandscape: false,
      ) {
    _controller.addActivityListener(_onActivity);
    _controller.addControlListener(_onControl);
  }

  /// The plugin shares a native player between controllers with the same id: one id per engine.
  static int _nextId = 1;
  static const _viewTimeout = Duration(seconds: 15);

  final NativeVideoPlayerController _controller;

  @override
  String get name => 'native';

  @override
  Future<void> open(PlayerSource source) async {
    try {
      // Completes once the native view exists: `buildView` must already be on screen.
      await _controller.initialize().timeout(_viewTimeout);
      if (isDisposed) return;
      final drm = source.drm;
      await _controller.load(
        url: source.url,
        headers: source.headers.isEmpty ? null : source.headers,
        // The licence server and its headers only: the keys stay in the platform's DRM module.
        drmConfig: drm == null
            ? null
            : {
                'type': drm.scheme,
                'licenseUrl': drm.licenseUrl,
                if (drm.certificateUrl != null) 'certificateUrl': drm.certificateUrl,
                if (drm.headers.isNotEmpty) 'headers': drm.headers,
              },
      );
    } catch (e) {
      final detail = e is PlatformException ? '${e.code}: ${e.message ?? ''}' : '$e';
      throw PlayerError(e is TimeoutException ? PlayerErrorKind.unknown : classifyPlayerError(detail), detail);
    }
    final error = value.error;
    if (error != null) throw error;
    _sync(initialized: true);
  }

  void _onActivity(PlayerActivityEvent event) {
    if (isDisposed) return;
    if (event.state == PlayerActivityState.error) {
      if (value.hasError) return;
      final detail = '${event.data?['message'] ?? event.data ?? ''}';
      value = value.copyWith(error: PlayerError(classifyPlayerError(detail), detail), playing: false, buffering: false);
      return;
    }
    _sync(state: event.state);
  }

  /// Position, duration and buffering arrive here several times a second.
  void _onControl(PlayerControlEvent event) {
    if (!isDisposed && event.state == PlayerControlState.timeUpdated) _sync();
  }

  void _sync({PlayerActivityState? state, bool? initialized}) {
    if (isDisposed || value.hasError) return;
    final activity = state ?? _controller.activityState;
    final buffering = activity == PlayerActivityState.buffering || activity == PlayerActivityState.loading;
    final playing = switch (activity) {
      PlayerActivityState.playing => true,
      // Waiting for data in the middle of playback is still "playing" for the controls.
      PlayerActivityState.buffering || PlayerActivityState.loading => value.playing,
      _ => false,
    };
    value = value.copyWith(
      initialized: initialized,
      playing: playing,
      buffering: buffering,
      position: _controller.currentPosition,
      duration: _controller.duration,
    );
  }

  @override
  Future<void> play() async {
    if (!isDisposed) await _controller.play();
  }

  @override
  Future<void> pause() async {
    if (!isDisposed) await _controller.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (!isDisposed) await _controller.seekTo(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (!isDisposed) await _controller.setVolume(volume.clamp(0.0, 1.0).toDouble());
  }

  @override
  Future<Duration?> get position async => isDisposed ? null : _controller.currentPosition;

  @override
  Widget buildView(BuildContext context) =>
      ColoredBox(color: const Color(0xFF000000), child: NativeVideoPlayer(controller: _controller));

  @override
  void dispose() {
    _controller.removeActivityListener(_onActivity);
    _controller.removeControlListener(_onControl);
    unawaited(_controller.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
