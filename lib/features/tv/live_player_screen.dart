import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_exception.dart';
import '../auth/session.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import 'fullscreen/fullscreen.dart';
import 'models.dart';

/// Plays a live channel stream (HLS), with its controls: back, channel name and « En direct »
/// at the top; play / pause, sound, « Revenir au direct » and full screen at the
/// bottom.
///
/// The controls hide after a few seconds of playback and come back on a tap, a mouse move or any
/// key (the first key press on a remote only shows them). Shortcuts: K (lecture), M (son),
/// F (plein écran), and the media keys of a remote.
///
/// Opened right away on a channel: the stream is asked for here ([loadStream]), under the same
/// spinner as the start of playback, so there is a single loading, not a dialog then the player.
class LivePlayerScreen extends ConsumerStatefulWidget {
  const LivePlayerScreen({super.key, required this.title, this.stream, this.loadStream, this.returnLocation})
    : assert(stream != null || loadStream != null);

  final String title;

  /// The stream, when already known.
  final TvStream? stream;

  /// Asks the API for the stream (`/tv/channels/{id}/stream`), when [stream] is not given.
  final Future<TvStream> Function()? loadStream;

  /// Channel page to return to after a guest signs in.
  final String? returnLocation;

  /// How long the controls stay on screen without any action, while playing.
  static const hideDelay = Duration(seconds: 4);

  /// How long the stream may "play" without its image moving before the error is shown.
  ///
  /// On the web, a stream the browser cannot decode (H.265…) makes hls.js fail, but
  /// video_player_web_hls cannot read that error: the controller says it plays while the screen
  /// stays black. The position not moving is the only sign of it (and of a stalled proxy).
  static const stallTimeout = Duration(seconds: 15);

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends ConsumerState<LivePlayerScreen> {
  VideoPlayerController? _controller;

  TvStream? _stream;

  /// Why the stream could not be obtained from the API (null: it was, or is being asked for).
  String? _loadError;
  bool _failed = false;
  bool _playing = false;
  bool _buffering = false;

  /// The image moves: the position changed since this source started. Until then, a spinner
  /// stays on screen with the controls (nothing to watch yet).
  bool _progressing = false;
  Duration? _lastPosition;
  Duration _stalledFor = Duration.zero;
  Timer? _watchdog;

  bool _controlsVisible = true;
  Timer? _hideTimer;
  bool _muted = false;
  double _volume = 1;

  /// The play / pause button: it gets the focus when the controls come back from a key press.
  final _playFocus = FocusNode(debugLabel: 'live-play');

  @override
  void initState() {
    super.initState();
    final stream = widget.stream;
    if (stream != null) {
      _use(stream);
    } else {
      _load();
    }
  }

  void _use(TvStream stream) {
    _stream = stream;
    _startCurrent();
  }

  /// Asks the API for the channel's stream, then plays it.
  Future<void> _load() async {
    setState(() {
      _failed = false;
      _loadError = null;
    });
    try {
      final stream = await widget.loadStream!();
      if (mounted) _use(stream);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loadError = e is ApiException ? e.message : null;
        _controlsVisible = true;
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _watchdog?.cancel();
    _controller?.dispose();
    _playFocus.dispose();
    exitFullscreen();
    super.dispose();
  }

  // ---------------------------------------------------------------------------------------------
  // Playback

  /// Builds the controller for the stream and plays it.
  Future<void> _startCurrent() async {
    if (!mounted) return;
    _watchdog?.cancel();

    setState(() {
      _failed = false;
      _playing = false;
      _buffering = false;
      _progressing = false;
    });
    _lastPosition = null;
    _stalledFor = Duration.zero;

    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    // The API hands the playable URL and the headers to send (some streams are signed).
    final controller = VideoPlayerController.networkUrl(Uri.parse(_stream!.url), httpHeaders: _stream!.headers);
    if (!mounted) {
      await controller.dispose();
      return;
    }
    _controller = controller;
    controller.addListener(() => _onValueChanged(controller));

    try {
      await controller.initialize();
    } catch (_) {
      _fail(controller);
      return;
    }
    if (!mounted || controller != _controller) return;
    if (controller.value.hasError) {
      _fail(controller);
      return;
    }

    await controller.setVolume(_muted ? 0 : _volume);
    // A live stream may need a user gesture to start on the web: a blocked play() leaves the
    // controller paused, and a tap (or the play button) starts it.
    await controller.play();
    if (!mounted || controller != _controller) return;
    setState(() {});
    _watchdog = Timer.periodic(_watchdogTick, (_) => _checkStall(controller));
  }

  static const _watchdogTick = Duration(milliseconds: 500);

  /// Watches the image move. A source that "plays" with a still image for
  /// [LivePlayerScreen.stallTimeout] shows the error; a pause (or a start refused by
  /// the browser) is not a stall.
  ///
  /// The position is asked to the player (`controller.position`): `value.position` is clamped to
  /// the duration, and a live stream on the web has none (it never moves there).
  Future<void> _checkStall(VideoPlayerController controller) async {
    if (controller != _controller || !mounted) return;
    final position = await controller.position;
    if (controller != _controller || !mounted) return;

    // The first position seen is only a reference: a live stream can start anywhere.
    final moved = position != null && _lastPosition != null && position != _lastPosition;
    _lastPosition = position;
    if (moved) {
      _stalledFor = Duration.zero;
      if (!_progressing) {
        setState(() => _progressing = true);
        _scheduleHide();
      }
    } else if (controller.value.isPlaying) {
      _stalledFor += _watchdogTick;
      if (_stalledFor >= LivePlayerScreen.stallTimeout) _fail(controller);
    } else {
      _stalledFor = Duration.zero;
    }
  }

  void _onValueChanged(VideoPlayerController controller) {
    if (controller != _controller || !mounted) return;
    final value = controller.value;
    if (value.hasError) {
      _fail(controller);
      return;
    }
    if (value.isPlaying != _playing || value.isBuffering != _buffering) {
      final started = value.isPlaying && !_playing;
      setState(() {
        _playing = value.isPlaying;
        _buffering = value.isBuffering;
      });
      if (started) {
        _scheduleHide();
      } else if (!value.isPlaying) {
        // Paused (or refused to start): the controls stay until playback resumes.
        _hideTimer?.cancel();
        setState(() => _controlsVisible = true);
      }
    }
  }

  /// Shows the error (with « Réessayer ») when [failed], the current controller, refuses to play.
  ///
  /// A failure is reported twice (the controller's error and the end of `initialize`): only the
  /// first counts, since the controller is no longer the current one after it.
  void _fail(VideoPlayerController failed) {
    if (failed != _controller || !mounted) return;
    _watchdog?.cancel();
    _hideTimer?.cancel();
    _controller = null;
    // Not during its own notification (ChangeNotifier forbids it): right after.
    Future.microtask(failed.dispose);
    setState(() {
      _failed = true;
      _playing = false;
      _controlsVisible = true;
    });
  }

  bool get _ready {
    final controller = _controller;
    return controller != null && controller.value.isInitialized && !controller.value.hasError;
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    _showControls();
  }

  /// Starts the stream again: after a pause, playback is behind the live edge.
  void _backToLive() {
    _showControls();
    _startCurrent();
  }

  void _retry() {
    final stream = _stream;
    if (stream == null) {
      _load();
    } else {
      _startCurrent();
    }
  }

  Future<void> _toggleMute() async {
    setState(() {
      _muted = !_muted;
      if (!_muted && _volume == 0) _volume = 1;
    });
    await _controller?.setVolume(_muted ? 0 : _volume);
    _showControls();
  }

  Future<void> _setVolume(double volume) async {
    setState(() {
      _volume = volume;
      _muted = volume == 0;
    });
    await _controller?.setVolume(volume);
    _showControls();
  }

  Future<void> _toggleFullscreen() async {
    if (isFullscreen()) {
      await exitFullscreen();
    } else {
      await enterFullscreen();
    }
    if (mounted) setState(() {});
    _showControls();
  }

  // ---------------------------------------------------------------------------------------------
  // Controls visibility

  /// The controls can hide only while the stream plays.
  bool get _canHide => _ready && _playing && _progressing && !_failed;

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_canHide) return;
    _hideTimer = Timer(LivePlayerScreen.hideDelay, () {
      if (mounted && _canHide) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted) return;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _onSurfaceTap() {
    // The browser refused to start playback on its own: the first tap starts it.
    final controller = _controller;
    if (controller != null && _ready && !controller.value.isPlaying) {
      _togglePlay();
      return;
    }
    if (_controlsVisible && _canHide) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  static final _backKeys = {LogicalKeyboardKey.escape, LogicalKeyboardKey.goBack, LogicalKeyboardKey.browserBack};

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Media keys of a remote, and the usual player shortcuts of a keyboard.
    if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.keyK) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      if (!_playing) _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPause || key == LogicalKeyboardKey.mediaStop) {
      if (_playing) _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF && !DeviceInfo.isTv) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

    if (_backKeys.contains(key)) return KeyEventResult.ignored;

    // Hidden controls: the first key (arrows, OK…) only brings them back, on play / pause.
    if (!_controlsVisible) {
      _showControls();
      _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    _scheduleHide();
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    final guest = ref.watch(sessionProvider.select((s) => s.isGuest));
    final controller = _controller;
    final ready = _ready;
    final visible = _controlsVisible || !_canHide;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: visible ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _showControls(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (guest)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 88,
                  left: 16,
                  right: 16,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Material(
                      color: const Color(0xE617243B),
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_outline_rounded, color: VxColors.accent, size: 18),
                            const SizedBox(width: 8),
                            const Text('Mode invité', style: TextStyle(color: Colors.white, fontSize: 13)),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => context.go(
                                '/connexion?redirect=${Uri.encodeComponent(widget.returnLocation ?? '/accueil')}',
                              ),
                              child: const Text('Se connecter'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onSurfaceTap,
                child: Center(
                  child: ready
                      ? AspectRatio(aspectRatio: controller!.value.aspectRatio, child: VideoPlayer(controller))
                      : null,
                ),
              ),
              if (_failed)
                _FailedMessage(message: _loadError, onRetry: _retry)
              else if (!ready || _buffering || (_playing && !_progressing))
                const IgnorePointer(
                  child: Center(child: CircularProgressIndicator(color: VxColors.accent)),
                )
              else if (!_playing)
                // Paused, or the browser refused to start playback on its own: ask for a tap.
                const IgnorePointer(
                  child: Center(child: Icon(Icons.play_circle_outline, size: 72, color: Colors.white70)),
                ),
              _Fade(
                visible: visible,
                alignment: Alignment.topCenter,
                child: _TopBar(
                  title: widget.title,
                  live: ready && _playing && _progressing,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              ),
              if (!_failed)
                _Fade(
                  visible: visible,
                  alignment: Alignment.bottomCenter,
                  child: _BottomBar(
                    playFocus: _playFocus,
                    ready: ready,
                    playing: _playing,
                    muted: _muted,
                    volume: _volume,
                    fullscreen: isFullscreen(),
                    onPlayPause: _togglePlay,
                    onMute: _toggleMute,
                    onVolume: _setVolume,
                    onBackToLive: _backToLive,
                    onFullscreen: _toggleFullscreen,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows or hides a bar of controls; hidden, it can be neither touched nor focused.
class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.alignment, required this.child});

  final bool visible;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(ignoring: !visible, child: child),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.live, required this.onBack});

  final String title;
  final bool live;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.tv(1) * 1.5 : 1.0;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 12 * s, layout.gutter, 32 * s),
          child: Row(
            children: [
              VxIconAction(icon: Icons.arrow_back_rounded, label: 'Retour', onPressed: onBack),
              SizedBox(width: 16 * s),
              Expanded(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: VxText.title(20 * s)),
              ),
              if (live) ...[SizedBox(width: 12 * s), _LiveBadge(scale: s)],
            ],
          ),
        ),
      ),
    );
  }
}

/// « En direct » with a red dot, while the stream plays.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6 * scale),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8 * scale,
            height: 8 * scale,
            decoration: const BoxDecoration(color: VxColors.dangerText, shape: BoxShape.circle),
          ),
          SizedBox(width: 6 * scale),
          Text('EN DIRECT', style: VxText.body(12 * scale, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.playFocus,
    required this.ready,
    required this.playing,
    required this.muted,
    required this.volume,
    required this.fullscreen,
    required this.onPlayPause,
    required this.onMute,
    required this.onVolume,
    required this.onBackToLive,
    required this.onFullscreen,
  });

  final FocusNode playFocus;
  final bool ready;
  final bool playing;
  final bool muted;
  final double volume;
  final bool fullscreen;
  final VoidCallback onPlayPause;
  final VoidCallback onMute;
  final ValueChanged<double> onVolume;
  final VoidCallback onBackToLive;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final gap = layout.isLarge ? layout.tv(20) : 12.0;
    // Phones and TVs have volume keys; a mouse needs a slider.
    final volumeSlider = !layout.isPhone && !DeviceInfo.isTv;
    final silent = muted || volume == 0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xE6000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, gap * 3, layout.gutter, gap * 1.5),
          child: FocusTraversalGroup(
            child: Row(
              children: [
                _PlayButton(focusNode: playFocus, playing: playing, onPressed: ready ? onPlayPause : null),
                SizedBox(width: gap),
                VxIconAction(
                  icon: silent ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  label: silent ? 'Activer le son' : 'Couper le son',
                  onPressed: onMute,
                ),
                if (volumeSlider)
                  SizedBox(
                    // A Slider takes all the height it is given: without one, the bar would fill
                    // the screen (and its gradient darken the whole image).
                    width: 120,
                    height: 48,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: VxColors.accent,
                        inactiveTrackColor: VxColors.line,
                        thumbColor: VxColors.accent,
                        overlayColor: VxColors.accent.withValues(alpha: 0.2),
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: muted ? 0 : volume,
                        semanticFormatterCallback: (v) => 'Volume ${(v * 100).round()} %',
                        onChanged: onVolume,
                      ),
                    ),
                  ),
                const Spacer(),
                if (ready) ...[
                  VxIconAction(icon: Icons.restart_alt_rounded, label: 'Revenir au direct', onPressed: onBackToLive),
                  SizedBox(width: gap),
                ],
                if (!DeviceInfo.isTv)
                  VxIconAction(
                    icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                    label: fullscreen ? 'Quitter le plein écran' : 'Plein écran',
                    onPressed: onFullscreen,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Play / pause: the screen's focus on arrival (remote), green like the main action.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.focusNode, required this.playing, required this.onPressed});

  final FocusNode focusNode;
  final bool playing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.isLarge ? layout.tv(88) : 60.0;
    final icon = playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
    return VxFocusable(
      focusNode: focusNode,
      autofocus: true,
      onPressed: onPressed ?? () {},
      onAccent: true,
      borderRadius: size,
      semanticLabel: playing ? 'Pause' : 'Lecture',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: onPressed == null ? VxColors.text.withValues(alpha: 0.12) : VxColors.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size * 0.55, color: onPressed == null ? VxColors.textMuted : VxColors.onAccent),
      ),
    );
  }
}

class _FailedMessage extends StatelessWidget {
  const _FailedMessage({required this.message, required this.onRetry});

  /// The API's message when the stream could not be obtained.
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: VxColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              message ?? 'Impossible de lire cette chaîne.',
              textAlign: TextAlign.center,
              style: VxText.body(16, color: VxColors.textSoft),
            ),
            const SizedBox(height: 24),
            VxButton(label: 'Réessayer', icon: Icons.refresh_rounded, autofocus: true, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
