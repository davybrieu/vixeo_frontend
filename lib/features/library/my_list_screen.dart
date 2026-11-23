import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/features.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../search/filter_bar.dart';
import '../search/search_filters.dart';
import '../social/social_repository.dart';
import '../tv/channel_search.dart';
import '../tv/channel_screen.dart';
import 'library.dart';

/// The titles a profile keeps: « À voir » (the default, « Ma liste » until 23/11/2026: the synced
/// favorites, first among the lists, `/listes/a-voir`), « J'aime » ❤ or « Vus » ([collection]),
/// with the search field, the filters (type, genre, years) and the order of the search page, plus
/// « Note » and « Mieux notés » on the rating each card shows (IMDb's, else TMDb's), applied here.
/// With [username], another member's (their profile page, `/membre/:username/a-voir`…), the same
/// page without the channels. Only my « À voir » has the channels.
class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key, this.username, this.collection = TitleCollection.toWatch});

  /// A member's titles; null: mine.
  final String? username;

  final TitleCollection collection;

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

/// What [MyListScreen] shows.
enum TitleCollection { toWatch, liked, watched }

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
    setState(() => _filters = filters);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final member = widget.username;
    final collection = widget.collection;
    final title = switch (collection) {
      TitleCollection.toWatch => 'À voir',
      TitleCollection.liked => member == null ? 'Mes J’aime' : 'Ses J’aime',
      TitleCollection.watched => member == null ? 'Mes titres vus' : 'Ses titres vus',
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VxPageHeader(
            title: title,
            // Opened from a profile page: a way back.
            back: GoRouter.maybeOf(context)?.canPop() ?? false,
            search: VxSearchField(
              controller: _searchController,
              fontSize: layout.size(16, tv: 24),
              onChanged: (value) {
                final query = value.trim();
                setState(() => _query = query);
              },
              onClear: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
            filters: SearchFilterBar(
              filters: _filters,
              withText: false,
              onChanged: _setFilters,
              // Saved titles and channels (a member's list, or while live TV is hidden: titles only):
              // no people, no channel category.
              kinds: member == null && collection == TitleCollection.toWatch && ref.watch(liveTvProvider)
                  ? const [SearchKind.all, SearchKind.movie, SearchKind.tv, SearchKind.channels]
                  : const [SearchKind.all, SearchKind.movie, SearchKind.tv],
              channelCategories: false,
              // Filtered and sorted here, on the rating each card shows (IMDb's, else TMDb's).
              withRating: true,
            ),
          ),
          Expanded(
            child: member == null
                ? _mine(context)
                : _member(context, switch (collection) {
                    TitleCollection.toWatch => socialTitlesProvider(member),
                    TitleCollection.liked => socialLikedProvider(member),
                    TitleCollection.watched => socialWatchedProvider(member),
                  }),
          ),
        ],
      ),
    );
  }

  /// A member's « À voir », likes or titles watched ([provider]).
  Widget _member(BuildContext context, FutureProvider<List<MediaItem>> provider) => AsyncView(
    value: ref.watch(provider),
    onRetry: () => ref.invalidate(provider),
    data: (titles) => _titles(
      context,
      titles,
      mine: false,
      onRefresh: () async {
        ref.invalidate(provider);
        await ref.read(provider.future);
      },
    ),
  );

  /// My « À voir »: channels (« Chaînes TV ») or titles, from the synced library. My likes and my
  /// titles watched: titles.
  Widget _mine(BuildContext context) {
    final layout = Layout.of(context);
    return AsyncView(
              value: ref.watch(libraryProvider),
              onRetry: () => ref.invalidate(libraryProvider),
              data: (state) {
                if (widget.collection != TitleCollection.toWatch) {
                  return _titles(
                    context,
                    widget.collection == TitleCollection.liked
                        ? [for (final item in state.liked) ?item.asMediaItem]
                        : state.watched,
                    mine: true,
                    onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                  );
                }
                if (_filters.kind.isChannels) {
                  final favoriteIds = state.favorites
                      .where((item) => item.type == 'channel')
                      .map((item) => item.itemId)
                      .toSet();
                  return ref
                      .watch(channelSearchProvider(('', null)))
                      .when(
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (error, _) =>
                            ErrorPanel(error: error, onRetry: () => ref.invalidate(channelSearchProvider(('', null)))),
                        data: (channels) {
                          final favorites = channels.where((channel) => favoriteIds.contains(channel.id)).toList();
                          if (favorites.isEmpty) {
                            return const EmptyState(
                              icon: Icons.live_tv_outlined,
                              title: 'Aucune chaîne à voir',
                              message: 'Ajoutez des chaînes TV à « À voir » pour les retrouver ici.',
                            );
                          }
                          return RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(channelSearchProvider(('', null)));
                              await ref.read(channelSearchProvider(('', null)).future);
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
                                    onTap: () => openChannel(context, channel),
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
                return _titles(
                  context,
                  [
                    for (final favorite in state.favorites)
                      if (favorite.tmdbTitle case final t?)
                        MediaItem(
                          id: t.id,
                          type: t.type,
                          title: favorite.title,
                          year: favorite.year,
                          posterUrl: favorite.posterUrl,
                          backdropUrl: favorite.backdropUrl,
                        ),
                  ],
                  mine: true,
                  onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                );
              },
    );
  }

  /// The movies and series of the list (most recently added first), completed by the catalog in
  /// one request (logo, rating, genres: never one per card), then searched, filtered and sorted.
  Widget _titles(
    BuildContext context,
    List<MediaItem> titles, {
    required bool mine,
    required Future<void> Function() onRefresh,
  }) {
    final refs = [for (final t in titles) (type: t.type, id: t.id)];
    final batch = ref.watch(titlesByIdProvider(titlesKey(refs)));
    _known.addAll(batch.value ?? const {});
    // First visit: the cards come with their logo, not before it.
    if (_known.isEmpty && refs.isNotEmpty && batch.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // « Note », « Votants » and « Mieux notés »: the rating each card shows (IMDb's, given with the
    // titles of the batch, else TMDb's) and its voters, ranges checked like the API's.
    double? ratingOf(MediaItem item) => item.shownRating?.$2.value;

    final matching = <MediaItem>[];
    final seen = <TitleRef>{};
    for (final title in titles) {
      final key = (type: title.type, id: title.id);
      // An episode in the list counts for its series: once.
      if (!seen.add(key)) continue;
      if (_filters.kind.mediaType != null && title.type != _filters.kind.mediaType) continue;
      if (_query.isNotEmpty && !title.title.toLowerCase().contains(_query.toLowerCase())) continue;

      final details = _known[key];
      final item = title.withDetails(details);
      if (!_filters.yearWithin(item.year)) continue;
      if (!_filters.ratingWithin(ratingOf(item), item.shownRating?.$2.votes ?? 0)) continue;
      if (_filters.genre != null && details != null && !details.genreIds.contains(_filters.genre!.id)) continue;
      matching.add(item);
    }

    switch (_filters.sortFor(withText: false)) {
      case SearchSort.rating:
        // Without any rating: last.
        matching.sort((a, b) => (ratingOf(b) ?? -1).compareTo(ratingOf(a) ?? -1));
        break;
      case SearchSort.recent:
        matching.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      case SearchSort.oldest:
        matching.sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
        break;
      case SearchSort.relevance:
      case SearchSort.popularity:
        // Keep the list's own order (most recently added first).
        break;
    }

    if (matching.isEmpty) {
      final isEmpty = titles.isEmpty;
      return switch (widget.collection) {
        TitleCollection.liked => EmptyState(
          icon: Icons.favorite_border_rounded,
          title: isEmpty ? (mine ? 'Aucun J’aime' : 'Aucun J’aime pour l’instant') : 'Aucun résultat',
          message: isEmpty
              ? (mine ? 'Aimez des films et des séries avec le cœur de leur fiche.' : null)
              : 'Aucun titre aimé ne correspond à cette recherche ou à ces filtres.',
        ),
        TitleCollection.watched => EmptyState(
          icon: Icons.visibility_outlined,
          title: isEmpty ? 'Aucun titre vu pour l’instant' : 'Aucun résultat',
          message: isEmpty
              ? (mine ? 'Les films et les séries marqués comme vus apparaîtront ici.' : null)
              : 'Aucun titre vu ne correspond à cette recherche ou à ces filtres.',
        ),
        TitleCollection.toWatch => EmptyState(
          icon: Icons.bookmark_border_rounded,
          title: isEmpty ? 'Rien à voir pour l’instant' : 'Aucun résultat',
          message: isEmpty
              ? (mine
                    ? 'Ajoutez des films et des séries à « À voir » depuis leur fiche pour les retrouver ici, sur tous '
                          'vos écrans.'
                    : 'Aucun film ni série à voir pour l’instant.')
              : 'Aucun titre à voir ne correspond à cette recherche ou à ces filtres.',
        ),
      };
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: PosterGrid(items: matching, alwaysScrollable: true, padding: pageContentPadding(context)),
    );
  }
}
