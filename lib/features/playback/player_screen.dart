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
  SourceProvider(id: 'frenchstream', name: 'FrenchStream'),
  SourceProvider(id: 'wiflix', name: 'Wiflix'),
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

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.controller,
    required this.currentSource,
    required this.format,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSources,
    required this.onExternal,
    required this.onBack,
  });

  final VideoPlayerController? controller;
  final StreamSource? currentSource;
  final String Function(Duration) format;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSources;
  final VoidCallback onExternal;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final value = controller?.value;
    final pos = value?.position ?? Duration.zero;
    final dur = value?.duration ?? Duration.zero;
    final playing = value?.isPlaying ?? false;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xE6000000), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentSource != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${currentSource!.provider} — ${currentSource!.name}',
                style: VxText.body(13, color: VxColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (value != null && value.isInitialized)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: VxColors.accent,
                inactiveTrackColor: VxColors.line,
                thumbColor: VxColors.accent,
                overlayColor: VxColors.accent.withValues(alpha: 0.2),
                trackHeight: 3,
              ),
              child: Slider(
                value: dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0,
                onChanged: (v) => onSeek(Duration(milliseconds: (v * dur.inMilliseconds).round())),
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: VxColors.text, size: 32),
                onPressed: onPlayPause,
              ),
              Text(format(pos), style: VxText.body(13, color: VxColors.textSoft)),
              Text(' / ', style: VxText.body(13, color: VxColors.textMuted)),
              Text(format(dur), style: VxText.body(13, color: VxColors.textMuted)),
              const Spacer(),
              IconButton(
                tooltip: 'Sources',
                icon: const Icon(Icons.list_rounded, color: VxColors.text),
                onPressed: onSources,
              ),
              IconButton(
                tooltip: 'Ouvrir en externe',
                icon: const Icon(Icons.open_in_new_rounded, color: VxColors.text),
                onPressed: onExternal,
              ),
              IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back_rounded, color: VxColors.text),
                onPressed: onBack,
              ),
            ],
          ),
        ],
      ),
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
  });

  final List<SourceProvider> providers;
  final Map<String, AsyncValue<List<StreamSource>>> sourcesByProvider;
  final StreamSource? current;
  final ValueChanged<StreamSource> onSelect;
  final ValueChanged<String> onRetry;
  final VoidCallback onClose;

  @override
  State<_SourcesPanel> createState() => _SourcesPanelState();
}

/// What a provider tile shows, and whether it can be opened.
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
    final match = RegExp(r'\b(2160P|4K|1080P|720P|576P|480P|360P|HD|SD)\b').firstMatch(value);
    return match?.group(0);
  }

  String _providerName(String id) => widget.providers
      .firstWhere(
        (p) => p.id == id,
        orElse: () => SourceProvider(id: id, name: id),
      )
      .name;

  @override
  Widget build(BuildContext context) {
    final selected = _selectedProvider;

    return Material(
      color: const Color(0xF0070A08),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  if (selected != null)
                    IconButton(
                      tooltip: 'Retour aux fournisseurs',
                      icon: const Icon(Icons.arrow_back_rounded, color: VxColors.textSoft),
                      onPressed: () => setState(() => _selectedProvider = null),
                    ),
                  Expanded(
                    child: Text(
                      selected == null ? 'Sources' : _providerName(selected),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.title(20),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: VxColors.textSoft),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            const Divider(color: VxColors.line, height: 1),
            Expanded(child: selected == null ? _providerList() : _linkList(selected)),
          ],
        ),
      ),
    );
  }

  /// Every provider is listed from the start. A tile opens its links only once they are
  /// found; while loading or after a failure it stays disabled (failure offers a retry).
  Widget _providerList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: widget.providers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
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

        return _ProviderTile(
          name: provider.name,
          status: status,
          linkCount: links.length,
          error: async?.error,
          onOpen: status == _ProviderStatus.links ? () => setState(() => _selectedProvider = provider.id) : null,
          onRetry: status == _ProviderStatus.failed ? () => widget.onRetry(provider.id) : null,
        );
      },
    );
  }

  Widget _linkList(String providerId) {
    final links = widget.sourcesByProvider[providerId]?.value ?? const <StreamSource>[];

    if (links.isEmpty) {
      return const Center(
        child: Text('Aucun lien pour ce fournisseur', style: TextStyle(color: VxColors.textMuted)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: links.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final source = links[index];
        final selected = widget.current?.url == source.url;
        return Material(
          color: selected ? VxColors.accent.withValues(alpha: 0.12) : const Color(0xFF111713),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => widget.onSelect(source),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.play_circle_filled_rounded : Icons.play_circle_outline_rounded,
                    color: VxColors.accent,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Lien ${index + 1}', style: VxText.body(15, weight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        Builder(
                          builder: (context) {
                            final language = _language(source);
                            final quality = _quality(source);
                            if (language == null && quality == null) {
                              return const SizedBox.shrink();
                            }
                            return Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (language != null) _SourceInfoChip(icon: Icons.language_rounded, label: language),
                                if (quality != null) _SourceInfoChip(icon: Icons.high_quality_rounded, label: quality),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: VxColors.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One provider row: its state ("Chargement en cours…", "Échec du chargement", a link
/// count), and a tap that opens its links — enabled only once they are found.
class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.name,
    required this.status,
    required this.linkCount,
    required this.onOpen,
    required this.onRetry,
    this.error,
  });

  final String name;
  final _ProviderStatus status;
  final int linkCount;
  final Object? error;
  final VoidCallback? onOpen;
  final VoidCallback? onRetry;

  String get _subtitle => switch (status) {
    _ProviderStatus.loading => 'Chargement en cours…',
    _ProviderStatus.failed => error is ApiException ? (error as ApiException).message : 'Échec du chargement',
    _ProviderStatus.empty => 'Aucun lien trouvé',
    _ProviderStatus.links => '$linkCount ${linkCount > 1 ? 'liens disponibles' : 'lien disponible'}',
  };

  Color get _subtitleColor => switch (status) {
    _ProviderStatus.failed => VxColors.error,
    _ProviderStatus.loading => VxColors.accent,
    _ => VxColors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    final enabled = onOpen != null;

    return Material(
      color: const Color(0xFF111713),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: VxColors.accent.withValues(alpha: enabled ? 0.12 : 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.dns_rounded, color: enabled ? VxColors.accent : VxColors.textMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: VxText.body(15, weight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(_subtitle, style: VxText.body(12, color: _subtitleColor)),
                  ],
                ),
              ),
              switch (status) {
                _ProviderStatus.loading => const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: VxColors.accent),
                ),
                _ProviderStatus.failed => IconButton(
                  tooltip: 'Réessayer',
                  icon: const Icon(Icons.refresh_rounded, color: VxColors.textSoft),
                  onPressed: onRetry,
                ),
                _ProviderStatus.empty => const Icon(Icons.block_rounded, color: VxColors.textMuted, size: 20),
                _ProviderStatus.links => const Icon(Icons.chevron_right_rounded, color: VxColors.textMuted),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceInfoChip extends StatelessWidget {
  const _SourceInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFF202923), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: VxColors.textMuted),
          const SizedBox(width: 4),
          Text(label, style: VxText.body(11, color: VxColors.textSoft)),
        ],
      ),
    );
  }
}
