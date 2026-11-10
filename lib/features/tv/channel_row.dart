import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/focusable.dart';
import 'channel_search.dart';
import 'models.dart';
import 'tv_repository.dart';

/// One row of live channels on the home page.
@immutable
class ChannelSection {
  const ChannelSection(this.title, this.channels);

  final String title;
  final List<TvChannel> channels;
}

/// A few channels per home row (keeps the page light; the search page has them all).
const homeChannelLimit = 24;

/// The home rows of live channels, in this order, with the words their category name contains
/// (lower case, without accents). A panel's categories have names of their own (« FR | SPORTS »,
/// « Jeunesse »…): every category that matches feeds the row.
const _homeChannelThemes = [
  ('Chaînes TV généralistes', ['general', 'tnt']),
  ('Chaînes TV sport', ['sport']),
  ('Chaînes TV info', ['info', 'news', 'actualite']),
  ('Chaînes TV enfants', ['enfant', 'kids', 'jeunesse', 'cartoon', 'dessins anim']),
];

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c');

/// Sorts [channels] into the home rows (généralistes, sport, info, enfants) from the name of their
/// category; empty rows are left out. When no category matches (a panel naming them otherwise),
/// a single « Chaînes TV » row, so the home page always shows channels when there are some.
List<ChannelSection> channelSections(List<TvCategory> categories, List<TvChannel> channels) {
  // Some providers have no list of categories: the category id is then its name.
  final names = {for (final c in categories) c.id: c.name};
  String categoryOf(TvChannel c) => _fold(names[c.categoryId] ?? c.categoryId);

  final sections = <ChannelSection>[];
  for (final (title, words) in _homeChannelThemes) {
    final matching = channels.where((c) {
      final category = categoryOf(c);
      return words.any(category.contains);
    });
    final row = matching.take(homeChannelLimit).toList();
    if (row.isNotEmpty) sections.add(ChannelSection(title, row));
  }
  if (sections.isEmpty && channels.isNotEmpty) {
    sections.add(ChannelSection('Chaînes TV', channels.take(homeChannelLimit).toList()));
  }
  return sections;
}

/// The home rows of live channels: categories and channels asked once, then sorted.
final homeChannelSectionsProvider = FutureProvider.autoDispose<List<ChannelSection>>((ref) async {
  final repository = ref.watch(tvRepositoryProvider);
  final results = await Future.wait([
    // Without categories (an error or none), the category ids are read as names.
    repository.categories().catchError((Object _) => const <TvCategory>[]),
    repository.channels(),
  ]);
  return channelSections(results[0] as List<TvCategory>, results[1] as List<TvChannel>);
});

/// Horizontal row of live channel tiles (home and search « Chaînes TV »).
class ChannelRow extends ConsumerWidget {
  const ChannelRow({super.key, required this.channels, this.title = 'Chaînes TV'});

  final List<TvChannel> channels;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (channels.isEmpty) return const SizedBox.shrink();

    final layout = Layout.of(context);
    final tileSize = layout.isLarge ? layout.tv(140).clamp(96, 160).toDouble() : 96.0;
    final gap = layout.isLarge ? layout.tv(20) : 10.0;
    final vPad = layout.isLarge ? layout.tv(12) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No « Voir tout »: all the channels are in the search page (« Chaînes TV »).
        Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.isLarge ? layout.tv(22) : 12),
          child: Text(title, style: VxText.title(layout.isLarge ? layout.tv(30) : 18)),
        ),
        FocusTraversalGroup(
          child: SizedBox(
            // The tile, then its name on up to two lines (12 px, line height 1.45).
            height: tileSize + 8 + 36 + vPad * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: vPad),
              itemCount: channels.length,
              separatorBuilder: (_, _) => SizedBox(width: gap),
              itemBuilder: (context, i) {
                final channel = channels[i];
                return ChannelTile(
                  channel: channel,
                  size: tileSize,
                  onTap: () => playLiveChannel(context, ref, channel),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A live channel: its logo in a square, its name under it. A press plays it.
class ChannelTile extends StatelessWidget {
  const ChannelTile({super.key, required this.channel, required this.size, required this.onTap});

  final TvChannel channel;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.14;
    return VxFocusable(
      borderRadius: radius,
      semanticLabel: channel.name,
      onPressed: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: ColoredBox(
                color: VxColors.surface,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: channel.logo != null && channel.logo!.isNotEmpty
                      ? Padding(
                          padding: EdgeInsets.all(size * 0.12),
                          child: Image.network(
                            channel.logo!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(Icons.live_tv, size: size * 0.4),
                          ),
                        )
                      : Icon(Icons.live_tv, size: size * 0.4, color: VxColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              channel.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: VxText.body(12, weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
