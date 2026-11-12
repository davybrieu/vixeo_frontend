import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_exception.dart';
import '../auth/session.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import 'playback.dart';

class StreamSource {
  const StreamSource({required this.provider, required this.name, required this.url});

  factory StreamSource.fromJson(Map<String, dynamic> json) => StreamSource(
    provider: json['provider'] as String? ?? '',
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );

  final String provider;
  final String name;
  final String url;
}

/// A provider the sources panel offers, as declared by the API.
class SourceProvider {
  const SourceProvider({required this.id, required this.name});

  factory SourceProvider.fromJson(Map<String, dynamic> json) =>
      SourceProvider(id: json['id'] as String? ?? '', name: json['name'] as String? ?? '');

  final String id;
  final String name;
}

/// Shown while the API's provider list is still loading, so the panel is never empty.
const kSourceProvidersFallback = <SourceProvider>[
  SourceProvider(id: 'tmdb-fr', name: 'TMDB Français (Onyx)'),
  SourceProvider(id: 'coflix', name: 'Coflix'),
  SourceProvider(id: 'aplouf', name: 'Aplouf'),
  SourceProvider(id: 'frenchstream', name: 'FrenchStream'),
  SourceProvider(id: 'frembed', name: 'Frembed'),
  SourceProvider(id: '1jour1film', name: '1Jour1Film'),
];

/// The providers to display, in order. Fetched once per title.
final sourceProvidersProvider = FutureProvider.family<List<SourceProvider>, PlaybackItem>((ref, item) async {
  final api = ref.read(apiClientProvider);
  final json = await api.get('/catalog/sources/providers');
  final data = json['data'];
  return data is List ? data.whereType<Map<String, dynamic>>().map(SourceProvider.fromJson).toList() : const [];
});

/// A title and the provider whose links are wanted.
typedef ProviderSourcesKey = ({PlaybackItem item, String provider});

/// The links one provider returns for one title.
///
/// Each provider is queried on its own so the panel can show it loading, failed, or with
/// its links — instead of blocking on a single request that fans out to every provider.
final providerSourcesProvider = FutureProvider.family<List<StreamSource>, ProviderSourcesKey>((ref, key) async {
  final api = ref.read(apiClientProvider);
  final item = key.item;
  final path = item.type == MediaType.movie
      ? '/catalog/movie/${item.id}/sources'
      : '/catalog/tv/${item.id}/season/${item.season}/episode/${item.episode}/sources';
  // A provider search can open a real browser on the server. The API allows up to 45
  // seconds for the scraper, so don't let the global 20-second API timeout cancel it.
  final json = await api.get(path, query: {'provider': key.provider}, receiveTimeout: const Duration(seconds: 65));
  final data = json['data'];
  return data is List ? data.whereType<Map<String, dynamic>>().map(StreamSource.fromJson).toList() : const [];
});

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.type, required this.id, this.season, this.episode});

  final MediaType type;
  final int id;
  final int? season;
  final int? episode;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _controller;
  StreamSource? _currentSource;
  bool _controlsVisible = true;
  // Onyx opens the source chooser as soon as a title enters playback.
  bool _sourcesPanelOpen = true;
  Timer? _hideTimer;
  String? _error;

  /// A source is being resolved (extractor running): show a spinner, block the panel.
  bool _resolving = false;

  PlaybackItem get _item => (type: widget.type, id: widget.id, season: widget.season, episode: widget.episode);

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_sourcesPanelOpen) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  /// Resolves the link through the API, then plays the resulting stream.
  ///
  /// The player never loads the raw player page: it can't be played and would leak the
  /// third-party page into the app. When the extractor fails, an error is shown instead.
  Future<void> _playSource(StreamSource source) async {
    setState(() {
      _error = null;
      _resolving = true;
      _currentSource = source;
      _sourcesPanelOpen = false;
    });
    _hideTimer?.cancel();

    await _controller?.dispose();
    _controller = null;

    final ResolvedStream resolved;
    try {
      resolved = await ref.read(playbackRepositoryProvider).resolve(source.url);
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
        _error = 'Impossible de lire cette source.';
      });
      return;
    }

    if (!mounted) return;
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(resolved.stream), httpHeaders: resolved.headers);
    _controller = ctrl;
    try {
      await ctrl.initialize();
      if (!mounted) return;
      setState(() => _resolving = false);
      await ctrl.play();
      _scheduleHide();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _error = 'Impossible de lire cette source.';
      });
    }
  }

  Future<void> _openExternal() async {
    if (_currentSource == null) return;
    final ok = await launchUrl(Uri.parse(_currentSource!.url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showVxSnack(context, 'Impossible d’ouvrir le lien.');
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final guest = ref.watch(sessionProvider.select((s) => s.isGuest));
    final playbackType = widget.type == MediaType.movie ? 'movie' : 'tv';
    final playbackLocation = '/lecture/$playbackType/${widget.id}'
        '${widget.season != null && widget.episode != null ? '?saison=${widget.season}&episode=${widget.episode}' : ''}';
    // Each provider is queried on its own so the panel can show it loading, failed, or
    // with its links, instead of one request that blocks on every provider at once.
    final declared = ref.watch(sourceProvidersProvider(_item)).value;
    final providers = (declared == null || declared.isEmpty) ? kSourceProvidersFallback : declared;
    final sourcesByProvider = {
      for (final provider in providers)
        provider.id: ref.watch(providerSourcesProvider((item: _item, provider: provider.id))),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _showControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video surface
            if (_controller != null && _controller!.value.isInitialized)
              Center(
                child: AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!)),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: VxColors.accent),
                    if (_resolving) ...[
                      const SizedBox(height: 16),
                      Text('Extraction du flux…', style: VxText.body(15, color: VxColors.textSoft)),
                    ],
                  ],
                ),
              ),

            // Top gradient + title
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Container(
                  height: 120,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),

            if (guest)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
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
            // Bottom controls
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _BottomControls(
                    controller: _controller,
                    currentSource: _currentSource,
                    format: _format,
                    onPlayPause: () {
                      final c = _controller;
                      if (c == null) return;
                      c.value.isPlaying ? c.pause() : c.play();
                      setState(() {});
                      _scheduleHide();
                    },
                    onSeek: (pos) => _controller?.seekTo(pos),
                    onSources: () => setState(() => _sourcesPanelOpen = true),
                    onExternal: _openExternal,
                    onBack: () => context.canPop() ? context.pop() : context.go('/accueil'),
                  ),
                ),
              ),
            ),

            // Sources side panel
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
                onClose: () => setState(() => _sourcesPanelOpen = false),
              ),
            ),

            // Keep playback errors above the video and all player controls so
            // the recovery actions remain visible and tappable.
            if (_error != null)
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
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: VxText.body(16, color: VxColors.textSoft),
                            ),
                            const SizedBox(height: 24),
                            VxButton(
                              label: 'Changer de source',
                              icon: Icons.list_rounded,
                              onPressed: () {
                                setState(() {
                                  _error = null;
                                  _sourcesPanelOpen = true;
                                  _controlsVisible = true;
                                });
                                _hideTimer?.cancel();
                              },
                            ),
                            const SizedBox(height: 12),
                            VxButton(label: 'Ouvrir en externe', icon: Icons.open_in_new, onPressed: _openExternal),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
