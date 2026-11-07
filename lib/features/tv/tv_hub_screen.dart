import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Live TV hub: categories + channel grid, play via resolved Xtream stream.
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

/// Minimal live player until the main PlayerScreen accepts arbitrary URLs.
class LivePlayerScreen extends StatelessWidget {
  const LivePlayerScreen({super.key, required this.title, required this.stream});

  final String title;
  final TvStream stream;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: VxText.title(20)),
              const SizedBox(height: 12),
              Text(
                'Flux ${stream.format.toUpperCase()} prêt.\n'
                'Brancher ici le lecteur existant (video_player / media_kit) avec :',
                textAlign: TextAlign.center,
                style: VxText.body(14, color: VxColors.textSoft),
              ),
              const SizedBox(height: 16),
              SelectableText(stream.url, style: VxText.body(12)),
            ],
          ),
        ),
      ),
    );
  }
}
