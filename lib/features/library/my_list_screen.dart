import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../search/filter_bar.dart';
import '../search/search_filters.dart';
import '../tv/channel_search.dart';
import 'library.dart';

/// "Ma liste": the active profile's favorites (synced between devices).
class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  SearchFilters _filters = const SearchFilters();

  /// Titles already read (logo, rating, genres), kept while the list changes.
  final _known = <TitleRef, MediaItem>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setFilters(SearchFilters filters) {
    setState(() => _filters = filters.forText(withText: false));
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final library = ref.watch(libraryProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VxPageHeader(
            title: 'Ma liste',
            search: VxSearchField(
              controller: _searchController,
              fontSize: layout.size(16, tv: 24),
              onChanged: (value) {
                final query = value.trim();
                setState(() {
                  _query = query;
                  _filters = _filters.forText(withText: false);
                });
              },
              onClear: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _filters = _filters.forText(withText: false);
                });
              },
            ),
            filters: SearchFilterBar(filters: _filters, withText: false, onChanged: _setFilters),
          ),
          Expanded(
            child: AsyncView(
              value: library,
              onRetry: () => ref.invalidate(libraryProvider),
              data: (state) {
                if (_filters.kind.isChannels) {
                  final favoriteIds = state.favorites
                      .where((item) => item.type == 'channel')
                      .map((item) => item.itemId)
                      .toSet();
                  return ref
                      .watch(channelSearchProvider(''))
                      .when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (error, _) =>
                            ErrorPanel(error: error, onRetry: () => ref.invalidate(channelSearchProvider(''))),
                        data: (channels) {
                          final favorites = channels.where((channel) => favoriteIds.contains(channel.id)).toList();
                          if (favorites.isEmpty) {
                            return const EmptyState(
                              icon: Icons.live_tv_outlined,
                              title: 'Aucune chaîne dans votre liste',
                              message: 'Ajoutez des chaînes TV à vos favoris pour les retrouver ici.',
                            );
                          }
                          return RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(channelSearchProvider(''));
                              await ref.read(channelSearchProvider('').future);
                            },
                            child: GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(layout.gutter, 8, layout.gutter, 24),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 160,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: favorites.length,
                              itemBuilder: (context, index) {
                                final channel = favorites[index];
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
                                                    errorBuilder: (_, _, _) => const Icon(Icons.live_tv, size: 40),
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
                            ),
                          );
                        },
                      );
                }
                // Every title of the list in one request (logo, rating, genres): never one per card.
                final refs = [
                  for (final favorite in state.favorites)
                    if (favorite.tmdbTitle case final t?) (type: t.type, id: t.id),
                ];
                final batch = ref.watch(titlesByIdProvider(titlesKey(refs)));
                _known.addAll(batch.value ?? const {});
                // First visit: the cards come with their logo, not before it.
                if (_known.isEmpty && refs.isNotEmpty && batch.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final matching = <({ProfileItem favorite, MediaItem item, double rating, int? year})>[];

                for (final favorite in state.favorites) {
                  final title = favorite.tmdbTitle;
                  if (title == null) continue;
                  if (_filters.kind.mediaType != null && title.type != _filters.kind.mediaType) continue;
                  if (_query.isNotEmpty && !favorite.title.toLowerCase().contains(_query.toLowerCase())) continue;

                  final details = _known[(type: title.type, id: title.id)];
                  final year = details?.year ?? favorite.year;
                  final rating = details?.voteAverage ?? 0;

                  final decade = _filters.decade;
                  if (decade != null && year != null && (year < (decade.from ?? 0) || year > decade.to)) {
                    continue;
                  }
                  if (_filters.minRating != null && details != null && rating < _filters.minRating!) {
                    continue;
                  }
                  if (_filters.genre != null && details != null && !details.genreIds.contains(_filters.genre!.id)) {
                    continue;
                  }

                  matching.add((
                    favorite: favorite,
                    item: MediaItem(
                      id: title.id,
                      type: title.type,
                      title: favorite.title,
                      year: year,
                      voteAverage: rating,
                      posterUrl: favorite.posterUrl ?? details?.posterUrl,
                      backdropUrl: favorite.backdropUrl ?? details?.backdropUrl,
                      logoUrl: details?.logoUrl,
                      logoAspectRatio: details?.logoAspectRatio,
                      summary: details?.summary,
                    ),
                    rating: rating,
                    year: year,
                  ));
                }

                switch (_filters.sortFor(withText: false)) {
                  case SearchSort.rating:
                    matching.sort((a, b) => b.rating.compareTo(a.rating));
                    break;
                  case SearchSort.recent:
                    matching.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
                    break;
                  case SearchSort.oldest:
                    matching.sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
                    break;
                  case SearchSort.relevance:
                  case SearchSort.popularity:
                    // Keep the library's existing order (most recently favorited first).
                    break;
                }

                final items = matching.map((entry) => entry.item).toList();
                if (items.isEmpty) {
                  final isEmpty = state.favorites.where((item) => item.tmdbTitle != null).isEmpty;
                  return EmptyState(
                    icon: Icons.bookmark_border_rounded,
                    title: isEmpty ? 'Votre liste est vide' : 'Aucun résultat',
                    message: isEmpty
                        ? 'Ajoutez des films et des séries avec « Ma liste » pour les retrouver ici, sur tous vos écrans.'
                        : 'Aucun titre de votre liste ne correspond à votre recherche ou à ces filtres.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                  child: PosterGrid(items: items, alwaysScrollable: true, padding: pageContentPadding(context)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
