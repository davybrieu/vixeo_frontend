import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';

import '../../core/device/layout.dart';
import '../../core/widgets/common.dart';
import 'channel_row.dart';
import 'channel_screen.dart';
import '../playback/player_screen.dart';
import 'models.dart';
import 'tv_repository.dart';

/// Live channels matching a text (empty = all) and a category (null = all), for the search page.
final channelSearchProvider = FutureProvider.autoDispose.family<List<TvChannel>, (String, String?)>((ref, key) {
  final (query, categoryId) = key;
  return ref.watch(tvRepositoryProvider).channels(query: query.isEmpty ? null : query, categoryId: categoryId);
});

/// Grid of live channels for the search page (type « Chaînes TV »), with the home row's tiles.
class ChannelSearchResults extends ConsumerWidget {
  const ChannelSearchResults({super.key, required this.query, this.categoryId});

  final String query;
  final String? categoryId;

  /// A grid of every channel stays light: the first ones only, a text or a category narrows it.
  static const maxShown = 200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final key = (query, categoryId);
    final async = ref.watch(channelSearchProvider(key));
    final tile = layout.isLarge ? layout.tv(140).clamp(96, 160).toDouble() : 96.0;
    final gap = layout.isLarge ? layout.tv(20) : 10.0;

    return async.when(
      loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorPanel(error: e, onRetry: () => ref.invalidate(channelSearchProvider(key))),
      ),
      data: (list) {
        if (list.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.live_tv_outlined,
              title: 'Aucune chaîne',
              message: query.isEmpty
                  ? 'Aucune chaîne disponible pour le moment.'
                  : 'Aucune chaîne ne correspond à « $query ».',
            ),
          );
        }
        final shown = list.length > maxShown ? list.take(maxShown).toList() : list;
        return SliverPadding(
          // Room for the focus zoom on TV.
          padding: EdgeInsets.fromLTRB(layout.gutter, layout.isLarge ? layout.tv(16) : 8, layout.gutter, 24),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: tile + gap,
              mainAxisExtent: tile + 52,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final channel = shown[i];
              return Align(
                alignment: Alignment.topCenter,
                child: ChannelTile(channel: channel, size: tile, onTap: () => openChannel(context, channel)),
              );
            },
          ),
        );
      },
    );
  }
}

/// Opens the live player at once; it asks for the stream itself (shared by hub and search).
///
/// On the root navigator: full screen, above the navigation (rail on large screens, tab bar on
/// phones), not inside the content area of the shell.
Future<void> playLiveChannel(BuildContext context, WidgetRef ref, TvChannel channel) {
  final repository = ref.read(tvRepositoryProvider);
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => PlayerScreen.live(
        title: channel.name,
        loadStream: () => repository.stream(channel.id),
        returnLocation: channelPath(channel.id),
        guestOverride: ref.read(sessionProvider).isGuest,
      ),
    ),
  );
}
