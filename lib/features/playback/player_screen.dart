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

/// Providers come only from the API (`/catalog/sources/providers`).
/// No catalogue list is hard-coded in the app.

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
  bool _sourcesPanelOpen = true;
  Timer? _hideTimer;
  String? _error;
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
    if (!ok && mounted) showVxSnack(context, "Impossible d'ouvrir le lien.");
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
    final providersAsync = ref.watch(sourceProvidersProvider(_item));
    final providers = providersAsync.value ?? const <SourceProvider>[];
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
                      Text('Extraction du flux...', style: VxText.body(15, color: VxColors.textSoft)),
                    ],
                  ],
                ),
              ),
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
                          const Text('Mode invite', style: TextStyle(color: Colors.white, fontSize: 13)),
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
                providersLoading: providersAsync.isLoading,
                providersError: providersAsync.hasError ? 'Impossible de charger les sources.' : null,
              ),
            ),
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
                            Text(_error!, textAlign: TextAlign.center, style: VxText.body(16, color: VxColors.textSoft)),
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
                '${currentSource!.provider} - ${currentSource!.name}',
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
              IconButton(tooltip: 'Sources', icon: const Icon(Icons.list_rounded, color: VxColors.text), onPressed: onSources),
              IconButton(tooltip: 'Ouvrir en externe', icon: const Icon(Icons.open_in_new_rounded, color: VxColors.text), onPressed: onExternal),
              IconButton(tooltip: 'Retour', icon: const Icon(Icons.arrow_back_rounded, color: VxColors.text), onPressed: onBack),
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
    this.providersLoading = false,
    this.providersError,
  });

  final List<SourceProvider> providers;
  final Map<String, AsyncValue<List<StreamSource>>> sourcesByProvider;
  final StreamSource? current;
  final ValueChanged<StreamSource> onSelect;
  final ValueChanged<String> onRetry;
  final VoidCallback onClose;
  final bool providersLoading;
  final String? providersError;

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
          child: Text('Aucun fournisseur disponible.', textAlign: TextAlign.center, style: VxText.body(14, color: VxColors.textSoft)),
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
