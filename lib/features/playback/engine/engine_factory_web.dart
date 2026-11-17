import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'player_engine.dart';
import 'player_errors.dart';
import 'video_player_engine.dart';
import 'web/browser_support_web.dart';
import 'web/hls_js_engine.dart';

/// The web: the browser's HTML5 player whenever it plays the stream itself, hls.js otherwise.
PlayerEngine createPlatformEngine(PlayerSource source) => WebPlayerEngine();

/// Chooses between the two web engines when the stream opens, and falls back from the first to
/// the second: a browser may claim it plays HLS ("maybe") and then give up on a given stream.
class WebPlayerEngine extends PlayerEngine {
  /// The engine that plays. A notifier of its own: the view follows it, whatever the state.
  final _engine = ValueNotifier<PlayerEngine?>(null);
  double? _volume;

  /// While the stream opens, a failure of the first engine is not the screen's business yet:
  /// the second engine may still play it.
  bool _opening = false;

  PlayerEngine? get _inner => _engine.value;

  @override
  String get name => _inner?.name ?? 'web';

  @override
  Future<void> open(PlayerSource source) async {
    final hls = source.isHls;
    final mediaSource = browserHasMediaSource();
    final choice = chooseWebEngine(
      hls: hls,
      nativeHls: hls && browserPlaysHlsNatively(),
      mediaSource: mediaSource,
      needsHeaders: browserHeaders(source.headers).isNotEmpty,
    );
    _opening = true;
    try {
      await _use(choice == WebEngineChoice.hlsJs ? HlsJsEngine() : VideoPlayerEngine()).open(source);
    } on PlayerError catch (error) {
      final retry =
          hls &&
          mediaSource &&
          choice == WebEngineChoice.html5 &&
          !isDisposed &&
          (error.kind == PlayerErrorKind.unsupported ||
              error.kind == PlayerErrorKind.decode ||
              error.kind == PlayerErrorKind.unknown);
      if (!retry) rethrow;
      final engine = _use(HlsJsEngine());
      await engine.open(source);
      final volume = _volume;
      if (volume != null) await engine.setVolume(volume);
    } finally {
      _opening = false;
    }
    _mirror();
  }

  /// Makes [engine] the one that plays, and mirrors its state.
  PlayerEngine _use(PlayerEngine engine) {
    final previous = _inner;
    previous?.removeListener(_mirror);
    _engine.value = engine;
    engine.addListener(_mirror);
    if (previous != null) Future.microtask(previous.dispose);
    return engine;
  }

  void _mirror() {
    final inner = _inner;
    if (inner == null || isDisposed) return;
    if (_opening && inner.value.hasError) return;
    value = inner.value;
  }

  @override
  Future<void> play() async => _inner?.play();

  @override
  Future<void> pause() async => _inner?.pause();

  @override
  Future<void> seekTo(Duration position) async => _inner?.seekTo(position);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _inner?.setVolume(volume);
  }

  @override
  Future<Duration?> get position async => _inner?.position;

  @override
  Widget buildView(BuildContext context) => ValueListenableBuilder<PlayerEngine?>(
    valueListenable: _engine,
    builder: (context, inner, _) {
      if (inner == null) return const SizedBox.expand();
      return KeyedSubtree(key: ObjectKey(inner), child: inner.buildView(context));
    },
  );

  @override
  void dispose() {
    final inner = _inner;
    inner?.removeListener(_mirror);
    inner?.dispose();
    _engine.dispose();
    super.dispose();
  }
}
