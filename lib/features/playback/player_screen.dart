import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/api/api_client.dart';
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

final streamSourcesProvider = FutureProvider.family<List<StreamSource>, PlaybackItem>((ref, item) async {
  final api = ref.read(apiClientProvider);
  final path = item.type == MediaType.movie
      ? '/catalog/movie/${item.id}/sources'
      : '/catalog/tv/${item.id}/season/${item.season}/episode/${item.episode}/sources';
  // Source discovery fans out to several providers (including browser-based
  // searches). The API allows up to 45 seconds for the scraper, so don't let
  // the global 20-second API timeout cancel this request prematurely.
  final json = await api.get(path, receiveTimeout: const Duration(seconds: 65));
  final data = json['data'];
  return data is List
      ? data.whereType<Map<String, dynamic>>().map(StreamSource.fromJson).toList()
      : const [];
});

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.type,
    required this.id,
    this.season,
    this.episode,
  });

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
  bool _sourcesPanelOpen = false;
  Timer? _hideTimer;
  String? _error;

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
      _currentSource = source;
      _sourcesPanelOpen = false;
    });
    _showControls();

    await _controller?.dispose();
    _controller = null;

    // Try to extract m3u8 via scraper if available, otherwise play direct
    String playUrl = source.url;
    try {
      final api = ref.read(apiClientProvider);
      final extracted = await api.post('/extract', body: {'url': source.url});
      if (extracted is Map && extracted['url'] is String) {
        playUrl = extracted['url'] as String;
      }
    } catch (_) {
      // No extract endpoint on Laravel yet — fall back to direct URL
    }

    final ctrl = VideoPlayerController.networkUrl(Uri.parse(playUrl));
    _controller = ctrl;
    try {
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {});
      await ctrl.play();
      _scheduleHide();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Impossible de lire cette source.');
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
    final sources = ref.watch(streamSourcesProvider(_item));

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
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
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
              )
            else
              const Center(child: CircularProgressIndicator(color: VxColors.accent)),

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
                sources: sources,
                current: _currentSource,
                onSelect: _playSource,
                onClose: () => setState(() => _sourcesPanelOpen = false),
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
    required this.sources,
    required this.current,
    required this.onSelect,
    required this.onClose,
  });

  final AsyncValue<List<StreamSource>> sources;
  final StreamSource? current;
  final ValueChanged<StreamSource> onSelect;
  final VoidCallback onClose;

  @override
  State<_SourcesPanel> createState() => _SourcesPanelState();
}

class _SourcesPanelState extends State<_SourcesPanel> {
  String? _selectedProvider;

  String _language(StreamSource source) {
    final value = source.name.toUpperCase();
    if (RegExp(r'\b(VOSTFR|VOSTA|SUBFR)\b').hasMatch(value)) return 'VOSTFR';
    if (RegExp(r'\b(VF|TRUEFRENCH|FRENCH|FR)\b').hasMatch(value)) return 'VF';
    if (RegExp(r'\b(VO|VOST)\b').hasMatch(value)) return 'VO';
    return 'Non précisée';
  }

  String _quality(StreamSource source) {
    final value = source.name.toUpperCase();
    final match = RegExp(r'\b(2160P|4K|1080P|720P|576P|480P|360P|HD|SD)\b').firstMatch(value);
    return match?.group(0) ?? 'Non précisée';
  }

  @override
  Widget build(BuildContext context) {
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
                  if (_selectedProvider != null)
                    IconButton(
                      tooltip: 'Retour aux serveurs',
                      icon: const Icon(Icons.arrow_back_rounded, color: VxColors.textSoft),
                      onPressed: () => setState(() => _selectedProvider = null),
                    ),
                  Expanded(
                    child: Text(
                      _selectedProvider ?? 'Sources',
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
            Expanded(
              child: AsyncView(
                value: widget.sources,
                data: (list) {
                  if (list.isEmpty) {
                    return const Center(
                      child: Text('Aucune source', style: TextStyle(color: VxColors.textMuted)),
                    );
                  }

                  final grouped = <String, List<StreamSource>>{};
                  for (final source in list) {
                    final provider = source.provider.trim().isEmpty ? 'Autre serveur' : source.provider.trim();
                    grouped.putIfAbsent(provider, () => []).add(source);
                  }

                  if (_selectedProvider != null) {
                    final links = grouped[_selectedProvider] ?? const <StreamSource>[];
                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: links.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final source = links[index];
                        final selected = widget.current?.url == source.url;
                        return Material(
                          color: selected
                              ? VxColors.accent.withValues(alpha: 0.12)
                              : const Color(0xFF111713),
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
                                        Text(
                                          'Lien \${index + 1}',
                                          style: VxText.body(15, weight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 7),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            _SourceInfoChip(icon: Icons.language_rounded, label: _language(source)),
                                            _SourceInfoChip(icon: Icons.high_quality_rounded, label: _quality(source)),
                                          ],
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

                  final providers = grouped.keys.toList();
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: providers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final provider = providers[index];
                      final count = grouped[provider]!.length;
                      return Material(
                        color: const Color(0xFF111713),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => _selectedProvider = provider),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: VxColors.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.dns_rounded, color: VxColors.accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(provider, style: VxText.body(15, weight: FontWeight.w700)),
                                      const SizedBox(height: 3),
                                      Text(
                                        '\$count \${count > 1 ? 'liens disponibles' : 'lien disponible'}',
                                        style: VxText.body(12, color: VxColors.textMuted),
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
                },
              ),
            ),
          ],
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
      decoration: BoxDecoration(
        color: const Color(0xFF202923),
        borderRadius: BorderRadius.circular(8),
      ),
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
