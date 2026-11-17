import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../player_engine.dart';
import '../player_errors.dart';
import 'browser_support_web.dart';
import 'hls_js_interop.dart';

/// HLS in a browser that does not play it on its own (Chrome, Firefox, Edge on a computer):
/// hls.js downloads the playlist and the segments and feeds a `<video>` element through Media
/// Source Extensions.
///
/// The `<video>` is a real DOM element shown inside Flutter by an `HtmlElementView` (a "platform
/// view": a hole in the Flutter canvas where the browser draws). It has no controls of its own
/// and ignores the mouse: the controls are the Flutter ones, the same as everywhere.
class HlsJsEngine extends PlayerEngine {
  HlsJsEngine() {
    _video
      ..autoplay = false
      ..controls = false
      ..playsInline = true;
    _video.style
      ..setProperty('width', '100%')
      ..setProperty('height', '100%')
      ..setProperty('object-fit', 'contain')
      ..setProperty('background-color', 'black')
      // Clicks go to Flutter (tap to pause, hover to show the controls).
      ..setProperty('pointer-events', 'none');
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _video);
  }

  static const _openTimeout = Duration(seconds: 30);
  static int _nextId = 0;

  final String _viewType = 'vixeo-hls-video-${_nextId++}';
  final web.HTMLVideoElement _video = web.HTMLVideoElement();
  final _domListeners = <(String, JSFunction)>[];

  Hls? _hls;
  Completer<void>? _opening;
  String _url = '';

  /// A decoding error can often be repaired by hls.js; twice at most, then it is an error.
  int _mediaRecoveries = 0;

  /// A fatal error is being sorted out (network or CORS?): the next ones add nothing.
  bool _failing = false;

  @override
  String get name => 'hls.js';

  @override
  Future<void> open(PlayerSource source) async {
    if (source.drm != null) {
      // No EME adapter yet (docs/lecteur.md): say so instead of showing a black picture.
      throw const PlayerError(PlayerErrorKind.drm, 'DRM is not implemented on the web');
    }
    if (!await ensureHlsJsLoaded() || !Hls.isSupported()) {
      throw const PlayerError(PlayerErrorKind.unsupported, 'hls.js is not available in this browser');
    }
    if (isDisposed) return;

    _url = source.url;
    final config = JSObject();
    final headers = browserHeaders(source.headers);
    if (headers.isNotEmpty) {
      config['xhrSetup'] = ((web.XMLHttpRequest xhr, JSAny? _) {
        // (No tear-off: `setRequestHeader` is a JavaScript method, it has to be called.)
        headers.forEach((name, value) => xhr.setRequestHeader(name, value));
      }).toJS;
    }

    final opening = _opening = Completer<void>();
    _listen('loadedmetadata', (_) => _onReady());
    _listen('canplay', (_) => _onReady());
    _listen('durationchange', (_) => _update());
    _listen('timeupdate', (_) => _update());
    _listen('playing', (_) => _update(playing: true, buffering: false));
    _listen('pause', (_) => _update(playing: false));
    _listen('ended', (_) => _update(playing: false, buffering: false));
    _listen('waiting', (_) => _update(buffering: true));
    _listen('canplaythrough', (_) => _update(buffering: false));
    _listen('seeked', (_) => _update(buffering: false));
    _listen('error', (_) => _onVideoError());

    final hls = _hls = Hls(config);
    hls.on('hlsError', ((JSAny? _, JSObject? data) => _onHlsError(data)).toJS);
    hls.on('hlsMediaAttached', ((JSAny? _, JSAny? _) => hls.loadSource(source.url)).toJS);
    hls.attachMedia(_video);

    await opening.future.timeout(
      _openTimeout,
      onTimeout: () => throw const PlayerError(PlayerErrorKind.network, 'the stream did not start in time'),
    );
  }

  void _listen(String type, void Function(web.Event event) handler) {
    final listener = handler.toJS;
    _video.addEventListener(type, listener);
    _domListeners.add((type, listener));
  }

  void _onReady() {
    final opening = _opening;
    if (opening != null && !opening.isCompleted) opening.complete();
    _update(initialized: true);
  }

  void _update({bool? initialized, bool? playing, bool? buffering}) {
    if (isDisposed) return;
    value = value.copyWith(
      initialized: initialized,
      playing: playing,
      buffering: buffering,
      position: _position,
      duration: _duration,
    );
  }

  Duration get _position => Duration(milliseconds: (_video.currentTime * 1000).round());

  /// Zero for a live stream (the browser says `Infinity`) and before the metadata (`NaN`).
  Duration get _duration {
    final seconds = _video.duration;
    return seconds.isFinite && seconds > 0 ? Duration(milliseconds: (seconds * 1000).round()) : Duration.zero;
  }

  // -----------------------------------------------------------------------------------------
  // Errors

  void _fail(PlayerError error) {
    if (isDisposed) return;
    final opening = _opening;
    if (opening != null && !opening.isCompleted) {
      opening.completeError(error);
    }
    value = value.copyWith(error: error, playing: false, buffering: false);
  }

  /// hls.js reports everything, including what it repairs by itself: only a fatal error stops
  /// playback.
  void _onHlsError(JSObject? data) {
    if (data == null || isDisposed || value.hasError || _failing) return;
    if (!_bool(data['fatal'])) return;
    final type = _string(data['type']);
    final details = _string(data['details']);
    final response = data['response'];
    final status = response != null && response.typeofEquals('object') ? _int((response as JSObject)['code']) : null;
    final kind = classifyHlsError(type: type, details: details, httpStatus: status);

    if (kind == PlayerErrorKind.decode && _mediaRecoveries < 2) {
      _mediaRecoveries++;
      _hls?.recoverMediaError();
      return;
    }
    final detail = '$type/$details${status == null ? '' : ' (HTTP $status)'}';
    if (kind == PlayerErrorKind.network && (status == null || status == 0)) {
      // No answer the page could read: the network, or a server that refuses this website.
      _failing = true;
      unawaited(
        looksLikeCorsRefusal(_url).then(
          (cors) => _fail(PlayerError(cors ? PlayerErrorKind.cors : PlayerErrorKind.network, detail)),
        ),
      );
      return;
    }
    _fail(PlayerError(kind, detail));
  }

  /// The `<video>` element's own error (`MediaError.code`: 2 network, 3 decoding, 4 format).
  void _onVideoError() {
    final error = _video.error;
    if (error == null || value.hasError) return;
    final kind = switch (error.code) {
      2 => PlayerErrorKind.network,
      3 => PlayerErrorKind.decode,
      4 => PlayerErrorKind.unsupported,
      _ => PlayerErrorKind.unknown,
    };
    _fail(PlayerError(kind, 'MediaError ${error.code}: ${error.message}'));
  }

  static bool _bool(JSAny? value) => value != null && value.typeofEquals('boolean') && (value as JSBoolean).toDart;

  static String _string(JSAny? value) =>
      value != null && value.typeofEquals('string') ? (value as JSString).toDart : '';

  static int? _int(JSAny? value) =>
      value != null && value.typeofEquals('number') ? (value as JSNumber).toDartDouble.round() : null;

  // -----------------------------------------------------------------------------------------
  // Commands

  @override
  Future<void> play() async {
    if (isDisposed) return;
    try {
      await _video.play().toDart;
    } catch (e) {
      // AbortError: a pause() arrived before the start, nothing to repair.
      if (isDisposed || '$e'.contains('AbortError')) return;
      // Most likely NotAllowedError: the browser did not see the viewer ask for this start
      // (autoplay policy). A muted start is always allowed.
      _video.muted = true;
      try {
        await _video.play().toDart;
        value = value.copyWith(autoplayMuted: true);
      } catch (_) {
        // Not even muted: the video stays paused, and a tap on the picture starts it.
      }
    }
  }

  @override
  Future<void> pause() async {
    if (!isDisposed) _video.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (!isDisposed) _video.currentTime = position.inMilliseconds / 1000;
  }

  @override
  Future<void> setVolume(double volume) async {
    if (isDisposed) return;
    _video
      ..muted = volume <= 0
      ..volume = volume.clamp(0.0, 1.0).toDouble();
    if (volume > 0 && value.autoplayMuted) value = value.copyWith(autoplayMuted: false);
  }

  @override
  Future<Duration?> get position async => isDisposed ? null : _position;

  @override
  Widget buildView(BuildContext context) => HtmlElementView(viewType: _viewType);

  @override
  void dispose() {
    for (final (type, listener) in _domListeners) {
      _video.removeEventListener(type, listener);
    }
    _domListeners.clear();
    try {
      _hls?.destroy();
    } catch (_) {}
    _hls = null;
    try {
      _video
        ..pause()
        ..removeAttribute('src')
        ..load();
    } catch (_) {}
    final opening = _opening;
    if (opening != null && !opening.isCompleted) {
      opening.completeError(const PlayerError(PlayerErrorKind.unknown, 'disposed'));
    }
    super.dispose();
  }
}
