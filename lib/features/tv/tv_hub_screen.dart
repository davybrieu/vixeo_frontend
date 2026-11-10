import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'channel_search.dart';
import 'models.dart';
import 'tv_repository.dart';

final _categoriesProvider = FutureProvider.autoDispose<List<TvCategory>>((ref) {
  return ref.watch(tvRepositoryProvider).categories();
});

final _channelsProvider = FutureProvider.autoDispose.family<List<TvChannel>, String?>((ref, categoryId) {
  return ref.watch(tvRepositoryProvider).channels(categoryId: categoryId);
});

/// Live TV hub: categories + channel grid, played from the API.
class TvHubScreen extends ConsumerStatefulWidget {
  const TvHubScreen({super.key});

  @override
  ConsumerState<TvHubScreen> createState() => _TvHubScreenState();
}

class _TvHubScreenState extends ConsumerState<TvHubScreen> {
  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(_categoriesProvider);
    final channels = ref.watch(_channelsProvider(_selectedCategoryId));
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, 16 * s, layout.gutter, 8 * s),
              child: Text('TV en direct', style: VxText.title(28 * s)),
            ),
            SizedBox(
              height: 44,
              child: categories.when(
                loading: () => const Center(
                  child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => const SizedBox.shrink(),
                data: (list) {
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Aucune catégorie.', style: VxText.body(14, color: VxColors.textSoft)),
                    );
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final all = i == 0;
                      final cat = all ? null : list[i - 1];
                      final selected = all ? _selectedCategoryId == null : _selectedCategoryId == cat!.id;
                      return ChoiceChip(
                        label: Text(all ? 'Toutes' : cat!.name),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => _selectedCategoryId = all ? null : cat!.id);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: channels.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EmptyState(
                      icon: Icons.live_tv_outlined,
                      title: 'TV indisponible',
                      message: '$e',
                    ),
                    const SizedBox(height: 16),
                    VxButton(
                      label: 'Réessayer',
                      kind: VxButtonKind.secondary,
                      onPressed: () {
                        ref.invalidate(_categoriesProvider);
                        ref.invalidate(_channelsProvider(_selectedCategoryId));
                      },
                    ),
                  ],
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.live_tv_outlined,
                      title: 'Aucune chaîne',
                      message: 'Aucune chaîne disponible pour le moment.',
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final channel = list[i];
                      return Material(
                        color: VxColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => playLiveChannel(context, ref, channel),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Expanded(
                                  child: channel.logo != null && channel.logo!.isNotEmpty
                                      ? Image.network(
                                          channel.logo!,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.live_tv, size: 40),
                                        )
                                      : const Icon(Icons.live_tv, size: 40),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  channel.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: VxText.body(13),
                                ),
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

/// Plays a live channel stream (HLS) with the headers the API asks for.
class LivePlayerScreen extends StatefulWidget {
  const LivePlayerScreen({super.key, required this.title, required this.stream});

  final String title;
  final TvStream stream;

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen> {
  VideoPlayerController? _controller;

  /// Playable URLs the server resolved for this channel, best first. A dead one is skipped for
  /// the next, so a channel that answers on several mirrors keeps working when one goes down.
  late final List<String> _sources;
  int _index = 0;
  bool _failed = false;
  bool _advancing = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    final resolved = widget.stream.sources.where((s) => s.isNotEmpty).toList();
    _sources = resolved.isEmpty ? [widget.stream.url] : resolved;
    _startCurrent();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Builds the controller for the current candidate, plays it, or moves on to the next one.
  Future<void> _startCurrent() async {
    if (!mounted) return;

    if (_index >= _sources.length) {
      setState(() {
        _failed = true;
        _playing = false;
      });
      return;
    }

    setState(() {
      _failed = false;
      _playing = false;
      _advancing = false;
    });

    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    // The API hands the playable URL and the headers to send (some streams are signed).
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(_sources[_index]),
      httpHeaders: widget.stream.headers,
    );
    if (!mounted) {
      await controller.dispose();
      return;
    }
    _controller = controller;
    controller.addListener(_onValueChanged);

    try {
      await controller.initialize();
    } catch (_) {
      _advance();
      return;
    }
    if (!mounted || controller != _controller) return;
    if (controller.value.hasError) {
      _advance();
      return;
    }

    // A live stream may need a user gesture to start on the web: a blocked play() surfaces as an
    // error on the controller, and a tap on the surface retries it. See _tapToPlay.
    await controller.play();
  }

  void _onValueChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.hasError) {
      _advance();
      return;
    }
    if (controller.value.isPlaying != _playing && mounted) {
      setState(() => _playing = controller.value.isPlaying);
    }
  }

  void _advance() {
    if (_advancing || !mounted) return;
    _advancing = true;
    _index++;
    _startCurrent();
  }

  /// Retries playback on a user tap: a programmatic play() is refused until the user interacts,
  /// which otherwise leaves the screen black on the web.
  Future<void> _tapToPlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isPlaying) {
      return;
    }
    await controller.play();
  }

  void _retry() {
    _index = 0;
    _startCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized && !controller.value.hasError;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tapToPlay,
        child: Center(
          child: _failed
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Impossible de lire cette chaîne.',
                        textAlign: TextAlign.center,
                        style: VxText.body(15, color: VxColors.textSoft),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _retry,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : ready
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                        // The browser refused to start playback on its own: ask for a tap.
                        if (!_playing)
                          const Icon(Icons.play_circle_outline, size: 64, color: Colors.white70),
                      ],
                    )
                  : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
