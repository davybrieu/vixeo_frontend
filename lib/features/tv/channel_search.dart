import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import 'models.dart';
import 'tv_hub_screen.dart';
import 'tv_repository.dart';

/// Live channels matching [query] (empty = all channels, capped for UI).
final channelSearchProvider = FutureProvider.autoDispose.family<List<TvChannel>, String>((ref, query) {
  return ref.watch(tvRepositoryProvider).channels(query: query.isEmpty ? null : query);
});

/// Grid of live channels for the search page (filter "Chaînes TV").
class ChannelSearchResults extends ConsumerWidget {
  const ChannelSearchResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final async = ref.watch(channelSearchProvider(query));

    return async.when(
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => NumberedSliverError(
        error: e,
        onRetry: () => ref.invalidate(channelSearchProvider(query)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.live_tv_outlined,
              title: 'Aucune chaîne',
              message: query.isEmpty
                  ? 'Aucune chaîne disponible. Vérifie la config Xtream côté serveur.'
                  : 'Aucune chaîne ne correspond à « $query ».',
            ),
          );
        }
        // Cap very large lists when browsing without a query.
        final shown = query.isEmpty && list.length > 200 ? list.take(200).toList() : list;
        return NumberedChannelGrid(channels: shown, layout: layout);
      },
    );
  }
}

class NumberedSliverError extends StatelessWidget {
  const NumberedSliverError({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return NumberedSliverFill(
      child: ErrorPanel(error: error, onRetry: onRetry),
    );
  }
}

class NumberedSliverFill extends StatelessWidget {
  const NumberedSliverFill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NumberedSliverToBox(child: SizedBox(height: 280, child: child));
  }
}

class NumberedSliverToBox extends StatelessWidget {
  const NumberedSliverToBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(child: child);
}

class NumberedChannelGrid extends ConsumerWidget {
  const NumberedChannelGrid({super.key, required this.channels, required this.layout});

  final List<TvChannel> channels;
  final Layout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final channel = channels[i];
            return Material(
              color: VxColors.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => playLiveChannel(context, ref, channel),
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
          childCount: channels.length,
        ),
      ),
    );
  }
}

/// Resolve stream and open the live player (shared by hub and search).
Future<void> playLiveChannel(BuildContext context, WidgetRef ref, TvChannel channel) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final stream = await ref.read(tvRepositoryProvider).stream(channel.id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LivePlayerScreen(title: channel.name, stream: stream),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}
