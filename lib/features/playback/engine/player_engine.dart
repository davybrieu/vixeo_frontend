/// The player's engine: what really plays the video, behind one interface.
///
/// `PlayerScreen` (the only player screen, with the only set of controls) talks to a
/// [PlayerEngine] and never to a plugin. Which engine plays depends on the platform
/// (`engine_factory.dart`):
///
/// - Android / iOS: `NativePlayerEngine` (better_native_video_player: ExoPlayer / AVPlayer);
/// - web: `VideoPlayerEngine` (video_player + video_player_web: the browser's HTML5 `<video>`)
///   when the browser plays the stream itself, `HlsJsEngine` (hls.js) for HLS elsewhere;
/// - anything else (desktop, tests): `VideoPlayerEngine`.
///
/// For a Vue developer: an engine is a small store (a `ValueNotifier`, like a `ref()`), whose
/// [PlayerEngineValue] the screen watches, plus a few commands (play, pause, seek, volume).
library;

import 'package:flutter/widgets.dart';

/// What kind of stream a URL is. The API says so; without it, the URL is read.
enum StreamFormat { hls, progressive }

/// Why playback failed, as far as the engine can tell.
enum PlayerErrorKind {
  /// The server cannot be reached, or stopped answering.
  network,

  /// The server answers, but does not allow this website to read the stream (CORS, web only).
  cors,

  /// The container or the codec is not one this browser / device plays (H.265 in Chrome…).
  unsupported,

  /// The stream started, then could not be decoded.
  decode,

  /// A protected stream (DRM) this engine cannot play.
  drm,

  /// Anything else.
  unknown,
}

/// A playback failure. [detail] is technical (logs, tests), never shown to the viewer.
@immutable
class PlayerError implements Exception {
  const PlayerError(this.kind, [this.detail = '']);

  final PlayerErrorKind kind;
  final String detail;

  @override
  bool operator ==(Object other) => other is PlayerError && other.kind == kind && other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, detail);

  @override
  String toString() => 'PlayerError(${kind.name}${detail.isEmpty ? '' : ': $detail'})';
}

/// Where a protected stream gets its licence. Nothing secret lives here: the licence server URL
/// and the request headers (a short-lived token) come from the API with the stream, and the
/// keys themselves never reach Flutter (the platform's CDM asks for them and keeps them).
@immutable
class DrmConfig {
  const DrmConfig({required this.scheme, required this.licenseUrl, this.certificateUrl, this.headers = const {}});

  /// "widevine" or "fairplay".
  final String scheme;
  final String licenseUrl;

  /// FairPlay only: the application certificate.
  final String? certificateUrl;
  final Map<String, String> headers;
}

/// What to play.
@immutable
class PlayerSource {
  const PlayerSource({required this.url, this.headers = const {}, this.format, this.live = false, this.drm});

  final String url;

  /// HTTP headers the player should send (Referer, a token…). A browser only sends them through
  /// hls.js, and never the ones it reserves (Referer, Origin, User-Agent…).
  final Map<String, String> headers;

  /// Null: guessed from the URL ([isHls]).
  final StreamFormat? format;
  final bool live;
  final DrmConfig? drm;

  bool get isHls => format != null ? format == StreamFormat.hls : looksLikeHls(url);
}

/// Whether [url] points to an HLS playlist, going by its path (`….m3u8`, with or without a query).
bool looksLikeHls(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  return path.toLowerCase().endsWith('.m3u8') || path.toLowerCase().endsWith('.m3u');
}

/// The API's name of a format ("hls", "m3u8", "mp4", "ts"…), null when it says nothing.
StreamFormat? streamFormatFromApi(String? name) => switch (name?.toLowerCase()) {
  'hls' || 'm3u8' => StreamFormat.hls,
  'mp4' || 'progressive' => StreamFormat.progressive,
  _ => null,
};

/// The state of an engine, as the controls need it.
@immutable
class PlayerEngineValue {
  const PlayerEngineValue({
    this.initialized = false,
    this.playing = false,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.autoplayMuted = false,
    this.error,
    this.aspectRatio,
  });

  /// The stream is open: there is a picture (or there is about to be one).
  final bool initialized;
  final bool playing;
  final bool buffering;
  final Duration position;

  /// Zero for a live stream.
  final Duration duration;

  /// The browser refused to start with sound, so playback started muted: the sound button shows
  /// « Activer le son », and pressing it (a real gesture) is allowed to turn the sound on.
  final bool autoplayMuted;
  final PlayerError? error;

  /// Width / height of the picture, once the engine knows it: the player frames the video with it
  /// (« Ajuster », « Remplir », « Zoom »).
  final double? aspectRatio;

  bool get hasError => error != null;

  PlayerEngineValue copyWith({
    bool? initialized,
    bool? playing,
    bool? buffering,
    Duration? position,
    Duration? duration,
    bool? autoplayMuted,
    PlayerError? error,
    double? aspectRatio,
  }) => PlayerEngineValue(
    initialized: initialized ?? this.initialized,
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    autoplayMuted: autoplayMuted ?? this.autoplayMuted,
    error: error ?? this.error,
    aspectRatio: aspectRatio ?? this.aspectRatio,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerEngineValue &&
      other.initialized == initialized &&
      other.playing == playing &&
      other.buffering == buffering &&
      other.position == position &&
      other.duration == duration &&
      other.autoplayMuted == autoplayMuted &&
      other.error == error &&
      other.aspectRatio == aspectRatio;

  @override
  int get hashCode =>
      Object.hash(initialized, playing, buffering, position, duration, autoplayMuted, error, aspectRatio);
}

/// One video being played. Created for one stream, disposed with it.
abstract class PlayerEngine extends ValueNotifier<PlayerEngineValue> {
  PlayerEngine() : super(const PlayerEngineValue());

  bool _disposed = false;

  /// Disposed engines ignore what their plugin still tells them.
  bool get isDisposed => _disposed;

  /// For logs and tests: "native", "html5", "hls.js".
  String get name;

  /// Opens [source], paused. The engine's view ([buildView]) must already be on screen: a
  /// native player only exists once its view does.
  ///
  /// Throws a [PlayerError] when the stream cannot be opened.
  Future<void> open(PlayerSource source);

  /// Starts playback. A browser may refuse a start it did not see the viewer ask for: the engine
  /// then starts muted ([PlayerEngineValue.autoplayMuted]) or stays paused, never fails.
  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  /// From 0 (muted) to 1.
  Future<void> setVolume(double volume);

  /// The position asked to the player itself: for a live stream, [PlayerEngineValue.position]
  /// may not move while this one does.
  Future<Duration?> get position;

  /// The picture, to fill the space given (letterboxed by the engine).
  Widget buildView(BuildContext context);

  @override
  set value(PlayerEngineValue newValue) {
    if (_disposed) return;
    super.value = newValue;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Builds the engine that plays [source] on this platform.
typedef PlayerEngineFactory = PlayerEngine Function(PlayerSource source);
