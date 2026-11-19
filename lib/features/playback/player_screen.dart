import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../addons/scraper_models.dart';
import '../addons/scrapers.dart';
import '../auth/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/models.dart';
import '../catalog/catalog_repository.dart';
import '../tv/models.dart';
import '../tv/fullscreen/fullscreen.dart';
import 'engine/engine_factory.dart';
import 'engine/player_engine.dart';
import 'engine/player_errors.dart';
import 'playback.dart';
import 'webvtt.dart';

class StreamSource {
  const StreamSource({
    required this.provider,
    required this.name,
    required this.url,
    this.stream,
    this.streamType,
    this.headers = const {},
    this.proxy = false,
  });

  factory StreamSource.fromJson(Map<String, dynamic> json) => StreamSource(
    provider: json['provider'] as String? ?? '',
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
    stream: json['stream'] as String?,
    streamType: json['stream_type'] as String?,
    headers: (json['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
  );

  /// A link a plug-in's scraper found (`docs/scrapers.md`). It is already playable, so nothing is
  /// resolved; in a browser it first goes through the server's stream proxy ([proxy]).
  factory StreamSource.fromScraper(ScraperStream stream, {required String provider, required String scraperName}) =>
      StreamSource(
        provider: provider,
        name: stream.label(scraperName),
        url: stream.url,
        stream: stream.url,
        streamType: stream.streamType,
        headers: stream.headers,
        proxy: kIsWeb,
      );

  final String provider;
  final String name;

  /// The link the server knows the source by (a player page, or the stream itself).
  final String url;

  /// Already playable: a plug-in's stream. Null: the link has to be resolved by the API first
  /// (`POST /catalog/resolve`).
  final String? stream;
  final String? streamType;

  /// HTTP headers to send with [stream].
  final Map<String, String> headers;

  /// A browser cannot send most headers nor read most sites (CORS): [stream] must first be given
  /// an address on our own origin (`POST /scrapers/stream`). Android and iOS play it as it is.
  final bool proxy;
}

/// A provider the sources panel offers, as declared by the API.
class SourceProvider {
  const SourceProvider({required this.id, required this.name});

  factory SourceProvider.fromJson(Map<String, dynamic> json) =>
      SourceProvider(id: json['id'] as String? ?? '', name: json['name'] as String? ?? '');

  final String id;
  final String name;
}

/// Providers are the scrapers of the installed plug-ins (`features/addons`, `docs/scrapers.md`) and
/// nothing else: each scraper that handles the title's type is one provider,
/// `scraper:{repository}:{id}`. No list is hard-coded in the app: Vixeo provides no repository.
/// Only the repositories turned on count, in the order chosen in « Plug-ins » (a repository is
/// turned on or off as a whole, never one scraper).
///
/// Why nothing is thrown when there is no plug-in: an empty list is a normal answer, the panel tells
/// the person that no plug-in is installed.
final sourceProvidersProvider = FutureProvider.family<List<SourceProvider>, PlaybackItem>((ref, item) async {
  final repos = await ref.watch(scraperReposProvider.future);
  return [
    for (final repo in repos.where((r) => r.enabled))
      for (final scraper in repo.scrapers)
        if (scraper.supports(item.type)) SourceProvider(id: scraper.providerId, name: scraper.name),
  ];
});

/// What the sources panel says when the account has no plug-in that gives sources.
const noPluginsInstalledMessage = "Aucun plug-in n'est installé.";

/// What it says when plug-ins are installed but all turned off in « Plug-ins ».
const pluginsDisabledMessage = 'Les plug-ins installés sont désactivés.';

/// A title and the provider whose links are wanted.
typedef ProviderSourcesKey = ({PlaybackItem item, String provider});

/// The links one provider returns for one title.
///
/// Each provider is queried on its own so the panel can show it loading, failed, or with
/// its links — instead of blocking on a single request that fans out to every provider. A scraper
/// runs on the device or on the server, as chosen for it (`ScraperService`); a scraper that was
/// removed since gives nothing.
final providerSourcesProvider = FutureProvider.family<List<StreamSource>, ProviderSourcesKey>((ref, key) async {
  final repos = await ref.read(scraperReposProvider.future);
  final match = findScraper(repos, key.provider);
  if (match == null || !match.repo.enabled) return const [];
  final streams = await ref.read(scraperServiceProvider).streams(match.repo, match.scraper, key.item);
  return [
    for (final stream in streams)
      StreamSource.fromScraper(stream, provider: key.provider, scraperName: match.scraper.name),
  ];
});

/// The player, for a title (sources, subtitles, episodes) and for a live channel ([PlayerScreen.live]).
///
/// Controls over the picture (demande du développeur, d'après un autre lecteur): the back button
/// at the top left, as on every page, and « EN DIRECT » at the top right (live); 10 s back,
/// play / pause and 10 s forward in the middle; at the bottom, what plays (title, year or episode,
/// « Via » its source), the seek bar, then the actions on the left (five at most, the others
/// behind an arrow that unfolds them) and the time on the right. They hide after a few seconds of
/// playback and come back on a tap, a mouse move or any key (the first key press on a remote only
/// shows them, on play / pause). Shortcuts: K (lecture), M (son), F (plein écran), J / L (10 s),
/// and the media keys of a remote.
///
/// This screen and its controls are the same on every platform. What plays the video is a
/// [PlayerEngine] (`engine/`): the native player on Android / iOS, the browser's on the web.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.type, required this.id, this.season, this.episode})
    : live = false, liveTitle = null, loadLiveStream = null, returnLocation = null, guestOverride = null;

  /// A live channel: the stream is asked for here ([loadStream]), under the same spinner as the
  /// start of playback, so there is a single loading, not a dialog then the player.
  const PlayerScreen.live({
    super.key,
    required String title,
    required Future<TvStream> Function() loadStream,
    this.returnLocation,
    this.guestOverride,
  }) : type = MediaType.movie,
       id = 0,
       season = null,
       episode = null,
       live = true,
       liveTitle = title,
       loadLiveStream = loadStream;

  final MediaType type;
  final int id;
  final int? season;
  final int? episode;
  final bool live;
  final String? liveTitle;
  final Future<TvStream> Function()? loadLiveStream;
  final String? returnLocation;
  final bool? guestOverride;

  /// How long the controls stay on screen without any action, while playing.
  static const hideDelay = Duration(seconds: 4);

  /// How long a live stream may "play" without its image moving before the error is shown.
  ///
  /// Engines report most failures themselves (network, format…), but not all: a stream may
  /// "play" while the screen stays black (a codec the device gives up on, a stalled proxy).
  /// The position not moving is the only sign of it.
  static const stallTimeout = Duration(seconds: 15);

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _liveError = 'Impossible de lire cette chaîne.';
  static const _sourceError = 'Impossible de lire cette source.';
  static const _watchdogTick = Duration(milliseconds: 500);
  static final _backKeys = {LogicalKeyboardKey.escape, LogicalKeyboardKey.goBack, LogicalKeyboardKey.browserBack};

  PlayerEngine? _engine;
  StreamSource? _currentSource;
  bool _controlsVisible = true;
  bool _sourcesPanelOpen = true;
  Timer? _hideTimer;
  String? _error;
  bool _resolving = false;
  bool _muted = false;
  double _volume = 1;
  List<CaptionCue> _captions = const [];
  String? _selectedSubtitle;
  int? _season;
  int? _episode;

  /// What the engine says (`value.playing`, `value.buffering`…), kept by [_onEngineValue]:
  /// a pause or a start comes from a button, a key, or the browser refusing to start on its own.
  bool _initialized = false;
  bool _playing = false;
  bool _buffering = false;

  /// The browser only allowed a muted start: the sound button was switched to « Activer le son ».
  bool _autoplayMuted = false;

  /// Live: the image moves (the position changed since the stream started). Until then, a spinner
  /// stays on screen with the controls (nothing to watch yet).
  bool _liveProgressing = false;
  Timer? _liveWatchdog;
  Duration? _lastLivePosition;
  Duration _liveStalledFor = Duration.zero;

  /// Live: the latest request for the stream. « Réessayer » or « Revenir au direct » pressed twice
  /// quickly must not leave two players running.
  int _liveAttempt = 0;

  /// The play / pause button: the screen's focus on arrival, and again when a key brings the
  /// controls back (remote).
  final _playFocus = FocusNode(debugLabel: 'player-play');

  PlaybackItem get _item => (type: widget.type, id: widget.id, season: _season, episode: _episode);

  @override
  void initState() {
    super.initState();
    // Always horizontal, full screen or not (demande du développeur).
    unawaited(lockLandscape());
    _season = widget.season;
    _episode = widget.episode;
    if (widget.live) {
      _sourcesPanelOpen = false;
      _loadLiveStream();
    } else if (widget.type == MediaType.tv && (_season == null || _episode == null)) {
      _loadFirstEpisode();
    }
  }

  Future<void> _loadFirstEpisode() async {
    // No episode: no source to look for, the error is shown alone.
    void noEpisode(String message) => setState(() {
      _error = message;
      _sourcesPanelOpen = false;
    });
    try {
      final details = await ref.read(titleProvider((MediaType.tv, widget.id)).future);
      if (!mounted) return;
      final available = details.seasons.where((season) => season.episodeCount > 0).toList();
      if (available.isEmpty) {
        noEpisode('Aucun épisode disponible pour cette série.');
        return;
      }
      final firstSeason = available.firstWhere(
        (season) => season.number > 0,
        orElse: () => available.first,
      );
      final season = await ref.read(seasonProvider((widget.id, firstSeason.number)).future);
      if (!mounted) return;
      if (season.episodes.isEmpty) {
        noEpisode('Aucun épisode disponible pour cette série.');
        return;
      }
      final first = season.episodes.first;
      setState(() {
        _season = first.seasonNumber;
        _episode = first.number;
        _error = null;
        _sourcesPanelOpen = true;
      });
    } catch (_) {
      if (mounted) noEpisode('Impossible de charger le premier épisode.');
    }
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.live && !oldWidget.live &&
        (widget.type != oldWidget.type || widget.id != oldWidget.id || widget.season != oldWidget.season || widget.episode != oldWidget.episode)) {
      unawaited(_stopPlayback());
      _season = widget.season;
      _episode = widget.episode;
      _currentSource = null;
      _error = null;
      _resolving = false;
      _sourcesPanelOpen = true;
      _controlsVisible = true;
      _captions = const [];
      if (widget.type == MediaType.tv && (_season == null || _episode == null)) {
        _loadFirstEpisode();
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _liveWatchdog?.cancel();
    _engine?.dispose();
    _playFocus.dispose();
    exitFullscreen();
    unlockOrientation();
    super.dispose();
  }

  // ---------------------------------------------------------------------------------------------
  // Playback

  /// Forgets the current engine (disposed) and the timers that watch it.
  Future<void> _stopPlayback() async {
    _hideTimer?.cancel();
    _liveWatchdog?.cancel();
    _lastLivePosition = null;
    _liveStalledFor = Duration.zero;
    _liveProgressing = false;
    _initialized = false;
    _playing = false;
    _buffering = false;
    _autoplayMuted = false;
    final previous = _engine;
    _engine = null;
    previous?.dispose();
  }

  /// Makes [engine] the current one (disposing any other) and follows its state.
  void _attach(PlayerEngine engine) {
    final previous = _engine;
    _engine = engine;
    if (previous != null && previous != engine) previous.dispose();
    engine.addListener(() => _onEngineValue(engine));
  }

  /// Opens [source] with this platform's engine, paused. Null when it cannot be played (the
  /// error is then on screen) or when another stream was asked for meanwhile.
  Future<PlayerEngine?> _open(PlayerSource source) async {
    final engine = ref.read(playerEngineFactoryProvider)(source);
    _attach(engine);
    // The engine's view goes on screen now: a native player only exists once its view does.
    setState(() {});
    try {
      await engine.open(source);
    } on PlayerError catch (error) {
      _fail(engine, error);
      return null;
    } catch (_) {
      _fail(engine);
      return null;
    }
    if (!mounted || engine != _engine) return null;
    return engine;
  }

  /// Live: asks the API for the channel's stream (`/tv/channels/{id}/stream`), then plays it.
  /// « Réessayer » and « Revenir au direct » come back here.
  Future<void> _loadLiveStream() async {
    final attempt = ++_liveAttempt;
    await _stopPlayback();
    if (!mounted || attempt != _liveAttempt) return;
    setState(() {
      _error = null;
      _resolving = true;
      _controlsVisible = true;
    });

    final TvStream stream;
    try {
      stream = await widget.loadLiveStream!();
    } catch (e) {
      if (!mounted || attempt != _liveAttempt) return;
      setState(() {
        _resolving = false;
        _error = e is ApiException ? e.message : _liveError;
      });
      return;
    }
    if (!mounted || attempt != _liveAttempt) return;
    _resolving = false;

    // The API hands the playable URL (on our own origin) and the headers to send.
    final engine = await _open(
      PlayerSource(
        url: stream.url,
        headers: stream.headers,
        format: streamFormatFromApi(stream.format),
        live: true,
      ),
    );
    if (engine == null) return;
    await engine.setVolume(_muted ? 0 : _volume);
    // A live stream may need a user gesture to start on the web: a refused play() starts muted
    // or leaves the engine paused, and a tap (or the play button) starts it.
    await engine.play();
    if (!mounted || engine != _engine) return;
    setState(() {});
    _liveWatchdog?.cancel();
    _liveWatchdog = Timer.periodic(_watchdogTick, (_) => _checkLiveProgress(engine));
  }

  Future<void> _playSource(StreamSource source) async {
    setState(() {
      _error = null;
      _resolving = true;
      _currentSource = source;
      _sourcesPanelOpen = false;
    });
    await _stopPlayback();

    final ResolvedStream resolved;
    try {
      // A plug-in's stream is already playable: nothing to resolve. In a browser it first gets an
      // address on our own origin, which adds the headers the site asks for.
      final direct = source.stream;
      if (direct == null || direct.isEmpty) {
        resolved = await ref.read(playbackRepositoryProvider).resolve(source.url);
      } else if (source.proxy) {
        resolved = await ref.read(playbackRepositoryProvider).proxyScraperStream(direct, source.headers);
      } else {
        resolved = ResolvedStream(stream: direct, streamType: source.streamType, headers: source.headers);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = _sourceError;
      });
      return;
    }

    if (!mounted) return;
    final engine = await _open(
      PlayerSource(
        url: resolved.stream,
        headers: resolved.headers,
        format: streamFormatFromApi(resolved.streamType),
      ),
    );
    if (engine == null) return;
    setState(() => _resolving = false);
    await engine.setVolume(_muted ? 0 : _volume);
    await engine.play();
  }

  /// Follows the engine: play / pause, buffering, and an error at any time (not only at the
  /// start).
  void _onEngineValue(PlayerEngine engine) {
    if (engine != _engine || !mounted) return;
    final value = engine.value;
    if (value.hasError) {
      _fail(engine, value.error);
      return;
    }
    // The browser refused to start with sound and started muted: the sound button says so, and
    // pressing it (a gesture the browser sees) turns the sound on.
    final mutedByBrowser = value.autoplayMuted && !_autoplayMuted;
    if (value.autoplayMuted != _autoplayMuted) {
      setState(() {
        _autoplayMuted = value.autoplayMuted;
        if (mutedByBrowser) _muted = true;
      });
    }
    if (value.playing == _playing && value.buffering == _buffering && value.initialized == _initialized) return;
    final started = value.playing && !_playing;
    final stopped = !value.playing && _playing;
    setState(() {
      _initialized = value.initialized;
      _playing = value.playing;
      _buffering = value.buffering;
      // Paused (or refused to start): the controls stay until playback resumes.
      if (stopped) _controlsVisible = true;
    });
    if (started) {
      _scheduleHide();
    } else if (stopped) {
      _hideTimer?.cancel();
    }
  }

  /// Shows the error when [failed], the current engine, cannot play: it refuses to start,
  /// breaks down, or (live) its image does not move. The sentence depends on the [cause] when
  /// the engine knows it (network, a server that refuses browsers, an unsupported format).
  ///
  /// A failure is reported twice (the engine's state and the end of `open`): only the first
  /// counts, since the engine is no longer the current one after it.
  void _fail(PlayerEngine failed, [PlayerError? cause]) {
    if (failed != _engine || !mounted) return;
    _liveWatchdog?.cancel();
    _hideTimer?.cancel();
    _engine = null;
    debugPrint('Player engine "${failed.name}" failed: ${cause ?? 'no picture'}');
    // Not during its own notification (ChangeNotifier forbids it): right after.
    Future.microtask(failed.dispose);
    setState(() {
      _error = playerErrorMessage(cause, fallback: widget.live ? _liveError : _sourceError, web: kIsWeb);
      _resolving = false;
      _initialized = false;
      _playing = false;
      _buffering = false;
      _controlsVisible = true;
    });
  }

  /// Live: watches the image move. A stream that "plays" with a still image for
  /// [PlayerScreen.stallTimeout] shows the error; a pause (or a start refused by the browser) is
  /// not a stall.
  ///
  /// The position is asked to the player (`engine.position`): `value.position` may be clamped to
  /// the duration, and a live stream has none (it never moves there).
  Future<void> _checkLiveProgress(PlayerEngine engine) async {
    if (engine != _engine || !mounted) return;
    final position = await engine.position;
    if (engine != _engine || !mounted) return;

    // The first position seen is only a reference: a live stream can start anywhere.
    final moved = position != null && _lastLivePosition != null && position != _lastLivePosition;
    _lastLivePosition = position;
    if (moved) {
      _liveStalledFor = Duration.zero;
      if (!_liveProgressing) {
        setState(() => _liveProgressing = true);
        _scheduleHide();
      }
    } else if (engine.value.playing) {
      _liveStalledFor += _watchdogTick;
      if (_liveStalledFor >= PlayerScreen.stallTimeout) _fail(engine);
    } else {
      _liveStalledFor = Duration.zero;
    }
  }

  bool get _ready {
    final engine = _engine;
    return engine != null && engine.value.initialized && !engine.value.hasError;
  }

  Future<void> _togglePlay() async {
    final engine = _engine;
    if (engine == null || !_ready) return;
    if (engine.value.playing) {
      await engine.pause();
    } else {
      await engine.play();
    }
    _showControls();
  }

  /// How the picture fills the screen (« Cadrage »): Ajuster, Remplir, Zoom, in turn.
  VideoFit _fit = VideoFit.contain;

  void _nextFit() {
    setState(() => _fit = VideoFit.values[(_fit.index + 1) % VideoFit.values.length]);
    showVxSnack(context, 'Cadrage : ${_fit.label}', icon: _fit.icon);
    _showControls();
  }

  /// Ten seconds back or forward: the buttons around play / pause, J / L, the media keys.
  static const _seekStep = Duration(seconds: 10);

  Future<void> _seekBy(Duration offset) async {
    final engine = _engine;
    if (engine == null || !_ready || widget.live) return;
    final value = engine.value;
    var target = value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (value.duration > Duration.zero && target > value.duration) target = value.duration;
    await engine.seekTo(target);
    _showControls();
  }

  /// Starts the stream again: after a pause, playback is behind the live edge.
  void _backToLive() {
    _showControls();
    // The button disappears until the stream is back: the remote's focus goes to play / pause.
    _playFocus.requestFocus();
    _loadLiveStream();
  }

  Future<void> _toggleMute() async {
    setState(() {
      _muted = !_muted;
      if (!_muted && _volume == 0) _volume = 1;
    });
    await _engine?.setVolume(_muted ? 0 : _volume);
    _showControls();
  }

  Future<void> _setVolume(double volume) async {
    setState(() {
      _volume = volume;
      _muted = volume == 0;
    });
    await _engine?.setVolume(volume);
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

  void _openSources() {
    _hideTimer?.cancel();
    setState(() {
      _sourcesPanelOpen = true;
      _controlsVisible = true;
    });
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/accueil');
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Controls visibility

  /// The controls can hide only while something plays (live: once the image moves), with no
  /// panel or error on screen.
  bool get _canHide =>
      _ready && _playing && _error == null && !_sourcesPanelOpen && (!widget.live || _liveProgressing);

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_canHide) return;
    _hideTimer = Timer(PlayerScreen.hideDelay, () {
      if (mounted && _canHide) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted) return;
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _onSurfaceTap() {
    // Paused, or the browser refused to start playback on its own: the tap starts it.
    final engine = _engine;
    if (engine != null && _ready && !engine.value.playing) {
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
    if (!widget.live && (key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.mediaRewind)) {
      _seekBy(-_seekStep);
      return KeyEventResult.handled;
    }
    if (!widget.live && (key == LogicalKeyboardKey.keyL || key == LogicalKeyboardKey.mediaFastForward)) {
      _seekBy(_seekStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF && !DeviceInfo.isTv) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }

    // Back leaves the player, even with the controls hidden.
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
  // Title: subtitles and episodes

  Future<void> _showSubtitles() async {
    try {
      final options = await ref.read(playbackRepositoryProvider).subtitles(_item);
      if (!mounted) return;
      if (options.isEmpty) {
        showVxSnack(context, 'Aucun sous-titre disponible.');
        return;
      }
      final choice = await showModalBottomSheet<SubtitleOption?>(
        context: context,
        backgroundColor: VxColors.surface,
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: Text('Sous-titres', style: VxText.title(18))),
            ListTile(
              leading: const Icon(Icons.subtitles_off_outlined),
              title: const Text('Désactivés'),
              onTap: () => Navigator.pop(sheetContext, null),
            ),
            for (final option in options)
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: Text(option.language.toUpperCase()),
                subtitle: option.release == null ? null : Text(option.release!),
                onTap: () => Navigator.pop(sheetContext, option),
              ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (!mounted) return;
      if (choice == null) {
        setState(() {
          _captions = const [];
          _selectedSubtitle = null;
        });
        return;
      }
      final vtt = await ref.read(playbackRepositoryProvider).subtitleFile(choice.fileId);
      if (!mounted) return;
      setState(() {
        _captions = parseWebVtt(vtt);
        _selectedSubtitle = choice.language;
      });
    } catch (_) {
      if (mounted) showVxSnack(context, 'Impossible de charger les sous-titres.');
    }
  }

  Future<void> _openEpisodes() async {
    final details = await ref.read(titleProvider((MediaType.tv, widget.id)).future);
    if (!mounted) return;
    final initialSeason = _season ?? (details.seasons.isNotEmpty ? details.seasons.first.number : null);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VxColors.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(children: [
                Expanded(child: Text('Épisodes · ${details.title}', style: VxText.title(18))),
                IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(child: ListView(children: [
              for (final season in details.seasons)
                FutureBuilder<Season>(
                  future: ref.read(seasonProvider((widget.id, season.number)).future),
                  builder: (context, snapshot) {
                    final episodes = snapshot.data?.episodes ?? const <Episode>[];
                    return ExpansionTile(
                      initiallyExpanded: season.number == initialSeason,
                      title: Text(season.name.isEmpty ? 'Saison ${season.number}' : season.name),
                      subtitle: Text('${season.episodeCount} épisodes'),
                      children: [
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
                        else if (snapshot.hasError)
                          const ListTile(title: Text('Impossible de charger les épisodes'))
                        else
                          for (final episode in episodes)
                            ListTile(
                              leading: Text('${episode.number}'.padLeft(2, '0')),
                              title: Text(episode.name.isEmpty ? 'Épisode ${episode.number}' : episode.name),
                              subtitle: Text('S${episode.seasonNumber} · Épisode ${episode.number}'),
                              trailing: episode.number == _episode && episode.seasonNumber == _season
                                  ? const Icon(Icons.equalizer_rounded, color: VxColors.accent)
                                  : const Icon(Icons.play_arrow_rounded),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _goToEpisode(episode.seasonNumber, episode.number);
                              },
                            ),
                      ],
                    );
                  },
                ),
            ])),
          ]),
        ),
      ),
    );
  }

  Future<void> _playNextEpisode() async {
    final details = await ref.read(titleProvider((MediaType.tv, widget.id)).future);
    if (!mounted) return;
    final seasonNumber = widget.season ?? (details.seasons.isNotEmpty ? details.seasons.first.number : null);
    if (seasonNumber == null) return;
    final season = await ref.read(seasonProvider((widget.id, seasonNumber)).future);
    if (!mounted) return;
    final index = season.episodes.indexWhere((e) => e.number == _episode);
    if (index >= 0 && index + 1 < season.episodes.length) {
      final next = season.episodes[index + 1];
      _goToEpisode(next.seasonNumber, next.number);
      return;
    }
    SeasonSummary? nextSeason;
    for (final candidate in details.seasons) {
      if (candidate.number > seasonNumber) { nextSeason = candidate; break; }
    }
    if (nextSeason == null) return;
    final nextData = await ref.read(seasonProvider((widget.id, nextSeason.number)).future);
    if (!mounted || nextData.episodes.isEmpty) return;
    _goToEpisode(nextData.episodes.first.seasonNumber, nextData.episodes.first.number);
  }

  void _goToEpisode(int season, int episode) {
    context.go('/lecture/tv/${widget.id}?saison=$season&episode=$episode');
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ---------------------------------------------------------------------------------------------
  // UI

  @override
  Widget build(BuildContext context) {
    final guest = widget.guestOverride ?? ref.watch(sessionProvider.select((s) => s.isGuest));
    final playbackType = widget.type == MediaType.movie ? 'movie' : 'tv';
    final playbackLocation = widget.live
        ? (widget.returnLocation ?? '/accueil')
        : '/lecture/$playbackType/${widget.id}'
            '${_season != null && _episode != null ? '?saison=$_season&episode=$_episode' : ''}';
    final canLoadSources = !widget.live &&
        (widget.type == MediaType.movie || (_season != null && _episode != null));
    final providersAsync = !canLoadSources
        ? const AsyncData<List<SourceProvider>>(<SourceProvider>[])
        : ref.watch(sourceProvidersProvider(_item));
    final providers = providersAsync.value ?? const <SourceProvider>[];
    final repos = canLoadSources
        ? (ref.watch(scraperReposProvider).value ?? const <ScraperRepo>[])
        : const <ScraperRepo>[];
    final noProvidersMessage = repos.isNotEmpty && !repos.any((r) => r.enabled)
        ? pluginsDisabledMessage
        : noPluginsInstalledMessage;
    final sourcesByProvider = <String, AsyncValue<List<StreamSource>>>{};
    if (canLoadSources) {
      for (final provider in providers) {
        sourcesByProvider[provider.id] = ref.watch(providerSourcesProvider((item: _item, provider: provider.id)));
      }
    }

    final engine = _engine;
    final ready = _ready;
    final visible = _controlsVisible || !_canHide;
    final error = _error;

    // Nothing to load yet: a title waits for a source to be chosen.
    final waiting = engine == null && !_resolving && !widget.live;
    // No picture yet, or (live) a picture that does not move: the play button turns into a
    // spinner; with the controls hidden (buffering), a spinner alone in the middle.
    final loading = !waiting && (!ready || _buffering || (widget.live && _playing && !_liveProgressing));
    final Widget? status = error == null && loading && !visible
        ? const IgnorePointer(child: Center(child: CircularProgressIndicator(color: VxColors.accent)))
        : null;

    // What plays, at the bottom left: the title, then its year (a movie) or its episode, then the
    // source it comes from.
    final details = widget.live ? null : ref.watch(titleProvider((widget.type, widget.id))).value;
    final episodeTitle = widget.live || widget.type != MediaType.tv || _season == null || _episode == null
        ? null
        : ref
              .watch(seasonProvider((widget.id, _season!)))
              .value
              ?.episodes
              .where((e) => e.number == _episode)
              .firstOrNull
              ?.name;
    final String? subtitle = widget.live
        ? null
        : widget.type == MediaType.tv && _season != null && _episode != null
        ? [
            'Saison $_season · Épisode $_episode',
            if (episodeTitle != null && episodeTitle.isNotEmpty) episodeTitle,
          ].join(' · ')
        : details?.year?.toString();
    final source = _currentSource;
    final providerName = source == null
        ? null
        : providers.where((p) => p.id == source.provider).firstOrNull?.name ?? source.provider;

    // The actions of the bottom bar, the most used first: five on screen, the others behind the
    // arrow.
    final layout = Layout.of(context);
    final fullscreen = isFullscreen();
    final actions = <Widget>[
      if (!widget.live)
        _BarAction(
          icon: Icons.closed_caption_outlined,
          label: 'Sous-titres',
          active: _selectedSubtitle != null,
          onPressed: _showSubtitles,
        ),
      _VolumeAction(
        silent: _muted || _volume == 0,
        volume: _muted ? 0 : _volume,
        // A mouse (web or desktop): phones and tablets in landscape have volume keys, and a green
        // slider there looked like the seek bar.
        slider: !DeviceInfo.isTv &&
            defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS,
        onMute: _toggleMute,
        onVolume: _setVolume,
      ),
      if (!widget.live) _BarAction(icon: Icons.cloud_outlined, label: 'Sources', onPressed: _openSources),
      if (widget.live && ready)
        _BarAction(icon: Icons.restart_alt_rounded, label: 'Revenir au direct', onPressed: _backToLive),
      _BarAction(icon: _fit.icon, label: 'Cadrage : ${_fit.label}', onPressed: _nextFit),
      if (!widget.live && widget.type == MediaType.tv) ...[
        _BarAction(icon: Icons.video_library_outlined, label: 'Épisodes', onPressed: _openEpisodes),
        _BarAction(icon: Icons.skip_next_rounded, label: 'Épisode suivant', onPressed: _playNextEpisode),
      ],
      if (!DeviceInfo.isTv)
        _BarAction(
          icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          label: fullscreen ? 'Quitter le plein écran' : 'Plein écran',
          onPressed: _toggleFullscreen,
        ),
    ];

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
              // The picture, drawn by the engine (a native view, a <video>…). It never gets the
              // pointer: taps and the mouse belong to the Flutter layers above, on every platform.
              if (engine != null)
                IgnorePointer(
                  child: ValueListenableBuilder<PlayerEngineValue>(
                    valueListenable: engine,
                    // The view is built once; only its frame follows the picture's shape.
                    child: KeyedSubtree(key: ObjectKey(engine), child: engine.buildView(context)),
                    builder: (context, value, view) =>
                        _FramedVideo(fit: _fit, aspectRatio: value.aspectRatio, child: view!),
                  ),
                ),
              GestureDetector(behavior: HitTestBehavior.opaque, onTap: _onSurfaceTap),
              if (status != null) status,
              if (engine != null && _captions.isNotEmpty)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  left: 24,
                  right: 24,
                  // Above the bottom bar while it shows.
                  bottom: visible ? layout.size(230, tv: 400) : layout.size(40, tv: 64),
                  child: ValueListenableBuilder<PlayerEngineValue>(
                    valueListenable: engine,
                    builder: (context, value, _) {
                      final caption = captionAt(_captions, value.position);
                      if (caption == null) return const SizedBox.shrink();
                      return IgnorePointer(
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.78),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Text(
                                caption,
                                textAlign: TextAlign.center,
                                style: VxText.body(18, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (guest == true)
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
                              onPressed: () => context.go('/connexion?redirect=${Uri.encodeComponent(playbackLocation)}'),
                              child: const Text('Se connecter'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (error == null)
                _Fade(
                  visible: visible,
                  // A little above the middle: the title of the bottom bar stays clear of it.
                  alignment: const Alignment(0, -0.15),
                  child: _CenterControls(
                    playFocus: _playFocus,
                    live: widget.live,
                    playing: _playing,
                    loading: loading,
                    // No source chosen yet: play opens the sources.
                    onPlayPause: waiting ? _openSources : _togglePlay,
                    onRewind: () => _seekBy(-_seekStep),
                    onForward: () => _seekBy(_seekStep),
                  ),
                ),
              if (error == null && _resolving && !widget.live)
                Align(
                  alignment: const Alignment(0, 0.3),
                  child: IgnorePointer(
                    child: Text('Extraction du flux...', style: VxText.body(15, color: VxColors.textSoft)),
                  ),
                ),
              if (error == null)
                _Fade(
                  visible: visible,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedBuilder(
                    // The time and the seek bar follow the video.
                    animation: Listenable.merge(engine == null ? const <Listenable>[] : <Listenable>[engine]),
                    builder: (context, _) {
                      final value = _engine?.value;
                      return _BottomBar(
                        title: widget.live ? widget.liveTitle : details?.title,
                        subtitle: subtitle,
                        providerName: providerName,
                        sourceName: source?.name,
                        live: widget.live,
                        ready: _ready,
                        position: value?.position ?? Duration.zero,
                        duration: value?.duration ?? Duration.zero,
                        format: _format,
                        actions: actions,
                        onInteract: _showControls,
                        onSeek: widget.live ? null : (Duration position) => _engine?.seekTo(position),
                      );
                    },
                  ),
                ),
              if (error != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xCC000000),
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: VxColors.error, size: 48),
                              const SizedBox(height: 16),
                              Text(error, textAlign: TextAlign.center, style: VxText.body(16, color: VxColors.textSoft)),
                              const SizedBox(height: 24),
                              if (widget.live)
                                VxButton(
                                  label: 'Réessayer',
                                  icon: Icons.refresh_rounded,
                                  autofocus: true,
                                  onPressed: _loadLiveStream,
                                )
                              else ...[
                                VxButton(
                                  label: 'Changer de source',
                                  icon: Icons.list_rounded,
                                  autofocus: true,
                                  onPressed: () {
                                    _hideTimer?.cancel();
                                    setState(() {
                                      _error = null;
                                      _sourcesPanelOpen = true;
                                      _controlsVisible = true;
                                    });
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Above the error: « Retour » stays within reach.
              _Fade(
                visible: visible,
                alignment: Alignment.topCenter,
                child: _TopBar(
                  live: widget.live && ready && _playing && _liveProgressing,
                  onBack: _goBack,
                ),
              ),
              if (!widget.live)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  top: 0,
                  bottom: 0,
                  right: _sourcesPanelOpen ? 0 : -380,
                  width: 360,
                  child: _SourcesPanel(
                    providers: providers,
                    sourcesByProvider: sourcesByProvider,
                    current: _currentSource,
                    onSelect: _playSource,
                    onRetry: (providerId) => ref.invalidate(providerSourcesProvider((item: _item, provider: providerId))),
                    onClose: () {
                      setState(() => _sourcesPanelOpen = false);
                      _scheduleHide();
                    },
                    providersLoading: !canLoadSources || providersAsync.isLoading,
                    providersError: providersAsync.hasError ? 'Impossible de charger les sources.' : null,
                    noProvidersMessage: noProvidersMessage,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows or hides a bar of controls; hidden, it cannot be touched.
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

/// Top of the controls: the back button at the top left, as on every page; « EN DIRECT » at the
/// top right while a live stream plays.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.live, required this.onBack});

  /// Live, and the image moves: « EN DIRECT ».
  final bool live;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
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
          // The same place as the back button of the other pages (VxPageHeader).
          padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.m), layout.gutter, layout.size(32, tv: 48)),
          child: Row(
            children: [
              VxBackButton(onPressed: onBack),
              const Spacer(),
              if (live) _LiveBadge(scale: layout.isLarge ? layout.tv(1) * 1.5 : 1.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// « EN DIRECT » with a red dot, while the stream plays.
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

/// The middle of the controls: 10 s back, play / pause (a spinner while there is no picture) and
/// 10 s forward; play / pause only for a live stream. Before a source is chosen, play opens the
/// sources.
class _CenterControls extends StatelessWidget {
  const _CenterControls({
    required this.playFocus,
    required this.live,
    required this.playing,
    required this.loading,
    required this.onPlayPause,
    required this.onRewind,
    required this.onForward,
  });

  final FocusNode playFocus;
  final bool live;
  final bool playing;
  final bool loading;
  final VoidCallback onPlayPause;
  final VoidCallback onRewind;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final seekSize = layout.size(44, tv: 80);
    final spacing = SizedBox(width: layout.size(40, tv: 100));
    return FocusTraversalGroup(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Always white and pressable (they do nothing until the video is there): greyed, they
          // could not be seen over a dark picture.
          if (!live) ...[
            _BarAction(
              icon: Icons.replay_10_rounded,
              label: 'Reculer de 10 secondes',
              size: seekSize,
              onPressed: onRewind,
            ),
            spacing,
          ],
          _PlayButton(
            focusNode: playFocus,
            playing: playing,
            loading: loading,
            onPressed: loading ? null : onPlayPause,
          ),
          if (!live) ...[
            spacing,
            _BarAction(
              icon: Icons.forward_10_rounded,
              label: 'Avancer de 10 secondes',
              size: seekSize,
              onPressed: onForward,
            ),
          ],
        ],
      ),
    );
  }
}

/// Play / pause: a large white sign, the screen's focus on arrival (remote).
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.focusNode, required this.playing, required this.loading, required this.onPressed});

  final FocusNode focusNode;
  final bool playing;

  /// No picture yet: a spinner in its place.
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.size(60, tv: 112);
    return VxFocusable(
      focusNode: focusNode,
      autofocus: true,
      // Always focusable: the remote's focus waits there while the picture loads.
      onPressed: onPressed ?? () {},
      borderRadius: size,
      semanticLabel: playing ? 'Pause' : 'Lecture',
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: loading
              ? SizedBox.square(
                  dimension: size * 0.5,
                  child: const CircularProgressIndicator(color: VxColors.accent, strokeWidth: 3),
                )
              : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: size, color: Colors.white),
        ),
      ),
    );
  }
}

/// An action of the controls: a white icon without a background, a round focus ring, a label for
/// screen readers (the tests look for it). Green while it is on (subtitles chosen).
class _BarAction extends StatelessWidget {
  const _BarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.size,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  /// Width and height of the button (the icon is a bit smaller); the bottom bar's by default.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final box = size ?? Layout.of(context).size(40, tv: 64);
    return VxFocusable(
      onPressed: onPressed,
      borderRadius: box,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: box,
        child: Icon(
          icon,
          size: box * 0.6,
          color: onPressed == null ? Colors.white38 : (active ? VxColors.accent : Colors.white),
        ),
      ),
    );
  }
}

/// The sound: on / off, and a volume slider with a mouse.
class _VolumeAction extends StatelessWidget {
  const _VolumeAction({
    required this.silent,
    required this.volume,
    required this.slider,
    required this.onMute,
    required this.onVolume,
  });

  final bool silent;
  final double volume;
  final bool slider;
  final VoidCallback onMute;
  final ValueChanged<double> onVolume;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BarAction(
          icon: silent ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          label: silent ? 'Activer le son' : 'Couper le son',
          onPressed: onMute,
        ),
        if (slider)
          SizedBox(
            // A Slider takes all the height it is given: without one, the bar would fill the
            // screen (and its gradient darken the whole image).
            width: 120,
            height: 48,
            child: SliderTheme(
              data: _sliderTheme(context),
              child: Slider(
                value: volume,
                semanticFormatterCallback: (v) => 'Volume ${(v * 100).round()} %',
                onChanged: onVolume,
              ),
            ),
          ),
      ],
    );
  }
}

/// Green progress on a light track, a small thumb: the seek bar and the volume.
SliderThemeData _sliderTheme(BuildContext context) => SliderTheme.of(context).copyWith(
  activeTrackColor: VxColors.accent,
  inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
  thumbColor: VxColors.accent,
  // Before the video is there the seek bar cannot move, but it shows as usual.
  disabledActiveTrackColor: VxColors.accent,
  disabledInactiveTrackColor: Colors.white.withValues(alpha: 0.28),
  disabledThumbColor: VxColors.accent,
  overlayColor: VxColors.accent.withValues(alpha: 0.2),
  trackHeight: 4,
  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
);

/// Bottom of the controls: what plays (title, year or episode, « Via » its source), the seek
/// bar, then the actions on the left (scrolling sideways when they do not fit) and the time on
/// the right.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.title,
    required this.subtitle,
    required this.providerName,
    required this.sourceName,
    required this.live,
    required this.ready,
    required this.position,
    required this.duration,
    required this.format,
    required this.actions,
    required this.onInteract,
    this.onSeek,
  });

  final String? title;

  /// The year of a movie, the season and episode of a show.
  final String? subtitle;

  /// The source playing: its provider (« Via … ») and its name (quality, size…).
  final String? providerName;
  final String? sourceName;
  final bool live;
  final bool ready;
  final Duration position;
  final Duration duration;
  final String Function(Duration) format;
  final List<Widget> actions;

  /// The icons were scrolled: the controls stay a little longer.
  final VoidCallback onInteract;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final gap = layout.size(12, tv: 20);
    final small = layout.size(15, tv: 26);
    final title = this.title;
    final subtitle = this.subtitle;
    final providerName = this.providerName;
    final sourceName = this.sourceName;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null && title.isNotEmpty)
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.title(layout.size(28, tv: 52)),
                ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(small, color: VxColors.textSecondary, weight: FontWeight.w600),
                ),
              if (providerName != null)
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Via $providerName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(small, color: VxColors.textSecondary, weight: FontWeight.w600),
                      ),
                    ),
                    if (sourceName != null && sourceName.isNotEmpty) ...[
                      SizedBox(width: gap / 2),
                      Icon(Icons.bolt_rounded, size: small * 1.3, color: VxColors.accent),
                      SizedBox(width: gap / 3),
                      Flexible(
                        child: Text(
                          sourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(small, color: VxColors.textSecondary, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              SizedBox(height: gap / 2),
              // A title always has its seek bar and its time, at 0 until the video is there.
              if (!live)
                SizedBox(
                  height: layout.size(32, tv: 48),
                  child: SliderTheme(
                    data: _sliderTheme(context),
                    child: Slider(
                      value: duration.inMilliseconds > 0
                          ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble()
                          : 0.0,
                      onChanged: ready && duration.inMilliseconds > 0
                          ? (v) => onSeek?.call(Duration(milliseconds: (v * duration.inMilliseconds).round()))
                          : null,
                    ),
                  ),
                ),
              FocusTraversalGroup(
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        // Too many icons for the width: they scroll sideways (finger, mouse, or the
                        // remote's focus), never under the time. Scrolling keeps the controls up.
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (_) {
                            onInteract();
                            return false;
                          },
                          child: ScrollConfiguration(
                            // A mouse drags the row too (web, computer).
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                                PointerDeviceKind.trackpad,
                                PointerDeviceKind.stylus,
                              },
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              // Room for the focus ring above and below.
                              padding: EdgeInsets.symmetric(vertical: gap / 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final (i, action) in actions.indexed) ...[
                                    if (i > 0) SizedBox(width: layout.size(8, tv: 16)),
                                    action,
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!live) ...[
                      SizedBox(width: gap),
                      Text(
                        '${format(position)} / ${format(duration)}',
                        style: VxText.body(layout.size(17, tv: 30), color: VxColors.text, weight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the picture fills the screen (« Cadrage »).
enum VideoFit {
  /// All of the picture, black bars where its shape differs from the screen's.
  contain('Ajuster', Icons.fit_screen_rounded),

  /// Stretched to the whole screen.
  fill('Remplir', Icons.aspect_ratio_rounded),

  /// The whole screen filled, the picture's edges cut.
  cover('Zoom', Icons.zoom_out_map_rounded);

  const VideoFit(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The picture in its frame. The view is laid out with the picture's own shape (the largest that
/// fits), then scaled to the screen: not at all (Ajuster), stretched (Remplir) or enlarged and cut
/// (Zoom). The tree is the same whatever the frame, so a native view is never built again. Until
/// the engine knows the shape, the view takes the whole screen, as before.
class _FramedVideo extends StatelessWidget {
  const _FramedVideo({required this.fit, required this.aspectRatio, required this.child});

  final VideoFit fit;
  final double? aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = constraints.biggest;
        final ratio = aspectRatio;
        var size = screen;
        if (ratio != null && ratio > 0 && screen.width > 0 && screen.height > 0) {
          size = screen.width / screen.height > ratio
              ? Size(screen.height * ratio, screen.height)
              : Size(screen.width, screen.width / ratio);
        }
        return ClipRect(
          child: FittedBox(
            fit: switch (fit) {
              VideoFit.contain => BoxFit.contain,
              VideoFit.fill => BoxFit.fill,
              VideoFit.cover => BoxFit.cover,
            },
            child: SizedBox.fromSize(size: size, child: child),
          ),
        );
      },
    );
  }
}

class _SourcesPanel extends StatefulWidget {
  const _SourcesPanel({
    required this.providers,
    required this.sourcesByProvider,
    required this.current,
    required this.onSelect,
    required this.onRetry,
    required this.onClose,
    this.providersLoading = false,
    this.providersError,
    this.noProvidersMessage = noPluginsInstalledMessage,
  });

  final List<SourceProvider> providers;
  final Map<String, AsyncValue<List<StreamSource>>> sourcesByProvider;
  final StreamSource? current;
  final ValueChanged<StreamSource> onSelect;
  final ValueChanged<String> onRetry;
  final VoidCallback onClose;
  final bool providersLoading;
  final String? providersError;

  /// Said when there is no provider: no plug-in installed, or all of them turned off.
  final String noProvidersMessage;

  @override
  State<_SourcesPanel> createState() => _SourcesPanelState();
}

enum _ProviderStatus { loading, failed, empty, links }

class _SourcesPanelState extends State<_SourcesPanel> {
  String? _selectedProvider;

  String? _language(StreamSource source) {
    final value = source.name.toUpperCase();
    if (RegExp(r'\b(VOSTFR|VOSTA|SUBFR)\b').hasMatch(value)) return 'VOSTFR';
    if (RegExp(r'\b(VF|TRUEFRENCH|FRENCH|FR)\b').hasMatch(value)) return 'VF';
    if (RegExp(r'\b(VO|VOST)\b').hasMatch(value)) return 'VO';
    return null;
  }

  String? _quality(StreamSource source) {
    final value = source.name.toUpperCase();
    final match = RegExp(r'\b(4K|2160P|1080P|720P|480P|360P|HD|SD)\b').firstMatch(value);
    return match?.group(1);
  }

  Widget _providerList() {
    if (widget.providersLoading && widget.providers.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: VxColors.accent));
    }
    if (widget.providersError != null && widget.providers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(widget.providersError!, textAlign: TextAlign.center, style: VxText.body(14, color: VxColors.textSoft)),
        ),
      );
    }
    if (widget.providers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(widget.noProvidersMessage, textAlign: TextAlign.center, style: VxText.body(14, color: VxColors.textSoft)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: widget.providers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final provider = widget.providers[index];
        final async = widget.sourcesByProvider[provider.id];
        final links = async?.value ?? const <StreamSource>[];
        final _ProviderStatus status;
        if (async == null || async.isLoading) {
          status = _ProviderStatus.loading;
        } else if (async.hasError) {
          status = _ProviderStatus.failed;
        } else if (links.isEmpty) {
          status = _ProviderStatus.empty;
        } else {
          status = _ProviderStatus.links;
        }
        final selected = _selectedProvider == provider.id;
        return Material(
          color: selected ? VxColors.accent.withValues(alpha: 0.12) : VxColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: status == _ProviderStatus.links
                ? () => setState(() => _selectedProvider = selected ? null : provider.id)
                : status == _ProviderStatus.failed
                    ? () => widget.onRetry(provider.id)
                    : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(provider.name, style: VxText.title(15)),
                        const SizedBox(height: 2),
                        Text(
                          switch (status) {
                            _ProviderStatus.loading => 'Recherche...',
                            _ProviderStatus.failed => 'Echec - appuyer pour reessayer',
                            _ProviderStatus.empty => 'Aucune source',
                            _ProviderStatus.links => '${links.length} source${links.length > 1 ? 's' : ''}',
                          },
                          style: VxText.body(12, color: VxColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (status == _ProviderStatus.loading)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: VxColors.accent))
                  else if (status == _ProviderStatus.failed)
                    const Icon(Icons.refresh_rounded, color: VxColors.error, size: 20)
                  else if (status == _ProviderStatus.links)
                    Icon(selected ? Icons.expand_less : Icons.expand_more, color: VxColors.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _linksFor(SourceProvider provider) {
    final async = widget.sourcesByProvider[provider.id];
    final links = async?.value ?? const <StreamSource>[];
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: links.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final source = links[index];
        final active = widget.current?.url == source.url;
        final lang = _language(source);
        final quality = _quality(source);
        return Material(
          color: active ? VxColors.accent.withValues(alpha: 0.15) : VxColors.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onSelect(source),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(source.name, style: VxText.title(14), maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (lang != null || quality != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            [if (lang != null) lang, if (quality != null) quality].join(' · '),
                            style: VxText.body(12, color: VxColors.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (active) const Icon(Icons.play_arrow_rounded, color: VxColors.accent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedProvider == null
        ? null
        : widget.providers.cast<SourceProvider?>().firstWhere(
              (p) => p?.id == _selectedProvider,
              orElse: () => null,
            );

    return Material(
      color: const Color(0xF00B1220),
      elevation: 12,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  if (selected != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: VxColors.text),
                      onPressed: () => setState(() => _selectedProvider = null),
                    ),
                  Expanded(child: Text(selected?.name ?? 'Sources', style: VxText.title(18))),
                  IconButton(icon: const Icon(Icons.close_rounded, color: VxColors.text), onPressed: widget.onClose),
                ],
              ),
            ),
            const Divider(height: 1, color: VxColors.line),
            Expanded(child: selected == null ? _providerList() : _linksFor(selected)),
          ],
        ),
      ),
    );
  }
}
