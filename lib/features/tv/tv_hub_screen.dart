import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../playback/player_screen.dart';
import 'models.dart';
import 'tv_repository.dart';

final _categoriesProvider = FutureProvider.autoDispose<List<TvCategory>>((ref) {
  return ref.watch(tvRepositoryProvider).categories();
});

final _selectedCategoryIdProvider = StateProvider.autoDispose<String?>((ref) => null);

final _channelsProvider = FutureProvider.autoDispose<List<TvChannel>>((ref) {
  final categoryId = ref.watch(_selectedCategoryIdProvider);
  return ref.watch(tvRepositoryProvider).channels(categoryId: categoryId);
});

/// Live TV hub: categories + channel grid, play via resolved Xtream stream.
class TvHubScreen extends ConsumerWidget {
  const TvHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(_categoriesProvider);
    final channels = ref.watch(_channelsProvider);
    final selectedId = ref.watch(_selectedCategoryIdProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('TV en direct', style: VxText.title(22)),
            ),
            SizedBox(
              height: 44,
              child: categories.when(
                loading: () => const Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('$e', style: VxText.body(14, color: VxColors.danger)),
                ),
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
                      final selected = all ? selectedId == null : selectedId == cat!.id;
                      return ChoiceChip(
                        label: Text(all ? 'Toutes' : cat!.name),
                        selected: selected,
                        onSelected: (_) {
                          ref.read(_selectedCategoryIdProvider.notifier).state = all ? null : cat!.id;
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
                error: (e, _) => EmptyState(
                  icon: Icons.live_tv_outlined,
                  title: 'TV indisponible',
                  subtitle: '$e',
                  action: VxButton(
                    label: 'Réessayer',
                    onPressed: () {
                      ref.invalidate(_categoriesProvider);
                      ref.invalidate(_channelsProvider);
                    },
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return const EmptyState(
                      icon: Icons.live_tv_outlined,
                      title: 'Aucune chaîne',
                      subtitle: 'Choisis une autre catégorie ou configure le panel Xtream côté serveur.',
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
                    itemBuilder: (context, i) => _ChannelTile(
                      channel: list[i],
                      onPlay: () => _play(context, ref, list[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref, TvChannel channel) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final stream = await ref.read(tvRepositoryProvider).stream(channel.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      // Reuse the existing player route with a live URL via extra until a dedicated live route exists.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LivePlayerScreen(title: channel.name, stream: stream),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel, required this.onPlay});

  final TvChannel channel;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VxColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPlay,
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
  }
}

/// Minimal live player until the main PlayerScreen accepts arbitrary URLs.
class LivePlayerScreen extends StatefulWidget {
  const LivePlayerScreen({super.key, required this.title, required this.stream});

  final String title;
  final TvStream stream;

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen> {
  @override
  Widget build(BuildContext context) {
    // Placeholder: open the existing player flow or media_kit/video_player with the URL.
    // For now we surface the resolved URL so integration with PlayerScreen can be completed next.
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: VxText.title(20)),
              const SizedBox(height: 12),
              Text(
                'Flux ${widget.stream.format.toUpperCase()} prêt.\n'
                'Brancher ici le lecteur existant (video_player / media_kit) avec :',
                textAlign: TextAlign.center,
                style: VxText.body(14, color: VxColors.textSoft),
              ),
              const SizedBox(height: 16),
              SelectableText(widget.stream.url, style: VxText.body(12)),
            ],
          ),
        ),
      ),
    );
  }
}
