import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import 'channel_screen.dart';
import 'models.dart';
import 'tv_repository.dart';

/// One row of live channels on the home page.
@immutable
class ChannelSection {
  const ChannelSection(this.title, this.channels, {this.categoryId});

  final String title;
  final List<TvChannel> channels;

  /// The category the row comes from (« Chaînes TV » page): its "see all" shows that category.
  final String? categoryId;
}

/// The name of a row of the « Chaînes TV » page in the row preferences: its category id.
String channelRowKey(ChannelSection section) => section.categoryId ?? section.title;

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

/// The rows of the « Chaînes TV » page: one per category, in the order of the categories, with
/// the first channels of each ([homeChannelLimit]); a category without channels is left out.
/// Channels of a category the list doesn't name come last, under their category id.
List<ChannelSection> channelCategorySections(List<TvCategory> categories, List<TvChannel> channels) {
  final byCategory = <String, List<TvChannel>>{};
  for (final channel in channels) {
    byCategory.putIfAbsent(channel.categoryId, () => []).add(channel);
  }
  ChannelSection section(String id, String title) =>
      ChannelSection(title, byCategory[id]!.take(homeChannelLimit).toList(), categoryId: id.isEmpty ? null : id);

  final known = {for (final c in categories) c.id};
  return [
    for (final c in categories)
      if (byCategory.containsKey(c.id)) section(c.id, c.name),
    for (final id in byCategory.keys)
      if (!known.contains(id)) section(id, id.isEmpty ? 'Autres chaînes' : id),
  ];
}

/// The rows of the « Chaînes TV » page: categories and channels asked once, then grouped.
final tvChannelRowsProvider = FutureProvider.autoDispose<List<ChannelSection>>((ref) async {
  final repository = ref.watch(tvRepositoryProvider);
  final results = await Future.wait([
    // Without categories (an error or none), the category ids are read as names.
    repository.categories().catchError((Object _) => const <TvCategory>[]),
    repository.channels(),
  ]);
  return channelCategorySections(results[0] as List<TvCategory>, results[1] as List<TvChannel>);
});

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

/// Horizontal row of live channel tiles (« Chaînes TV » page and search).
class ChannelRow extends ConsumerWidget {
  const ChannelRow({
    super.key,
    required this.channels,
    this.title = 'Chaînes TV',
    this.onSeeAll,
    this.autofocusFirst = false,
  });

  final List<TvChannel> channels;
  final String title;

  /// The round arrow on the right of the title (« Chaînes TV » page: the whole category).
  final VoidCallback? onSeeAll;

  /// The first tile takes the focus on arrival (first row of a page, on TV).
  final bool autofocusFirst;

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
        SectionHeader(title, onSeeAll: onSeeAll),
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
                  autofocus: autofocusFirst && i == 0,
                  onTap: () => openChannel(context, channel),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A live channel: its logo in a square, its name under it. A press opens it.
class ChannelTile extends ConsumerWidget {
  const ChannelTile({
    super.key,
    required this.channel,
    required this.size,
    required this.onTap,
    this.autofocus = false,
  });

  final TvChannel channel;
  final double size;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = size * 0.14;
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: radius,
      semanticLabel: channel.name,
      onPressed: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          children: [
            Stack(
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
                                // Web: an <img> element, so the logo host needs no CORS headers.
                                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                                errorBuilder: (_, _, _) => Icon(Icons.live_tv, size: size * 0.4),
                              ),
                            )
                          : Icon(Icons.live_tv, size: size * 0.4, color: VxColors.textSecondary),
                    ),
                  ),
                ),
              ],
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
