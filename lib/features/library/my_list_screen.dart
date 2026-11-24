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
import '../catalog/paging.dart';
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

  /// Titles shown, 20 by 20 ([pageSize]): more as the grid scrolls.
  int _shown = pageSize;
  late final _nextTitles = NextPage(() {
    if (mounted) setState(() => _shown += pageSize);
  });

  /// A search, a filter or an order: every title is looked at (a member's: every page, 20 a
  /// request).
  bool get _everything => _query.isNotEmpty || !_filters.isDefault;

  /// Filters that need what the catalog says of each title (genres, rating): its details for every
  /// title, 20 a request.
  bool get _needsDetails =>
      _filters.genre != null || _filters.hasRatingBounds || _filters.sortFor(withText: false) == SearchSort.rating;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setFilters(SearchFilters filters) {
    setState(() {
      _filters = filters;
      _shown = pageSize;
    });
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
                setState(() {
                  _query = query;
                  _shown = pageSize;
                });
              },
              onClear: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _shown = pageSize;
                });
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
                : _member(context, (page) => switch (collection) {
                    TitleCollection.toWatch => socialTitlesProvider((member, page)),
                    TitleCollection.liked => socialLikedProvider((member, page)),
                    TitleCollection.watched => socialWatchedProvider((member, page)),
                  }),
          ),
        ],
      ),
    );
  }

  /// A member's « À voir », likes or titles watched ([page]): 20 at a time, the next ones as the
  /// grid scrolls; every page (one after the other) for a search, a filter or an order.
  Widget _member(BuildContext context, FutureProvider<Paged<MediaItem>> Function(int page) page) =>
      PagedBuilder<MediaItem>(
        page: page,
        all: _everything,
        builder: (context, pages, nearEnd) {
          if (pages.error case final error?) {
            return ErrorPanel(error: error, onRetry: () => ref.invalidate(page(1)));
          }
          if (pages.loaded == 0) return const Center(child: CircularProgressIndicator());
          return _titles(
            context,
            pages.items,
            mine: false,
            complete: pages.complete,
            footer: PagedFooter(pages: pages, page: page),
            loadMore: () => nearEnd(pages.items.length, pages.items.length),
            onRefresh: () async {
              for (var p = 1; p <= pages.loaded; p++) {
                ref.invalidate(page(p));
              }
              await ref.read(page(1).future);
            },
          );
        },
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

  /// The movies and series of the list (most recently added first), completed by the catalog 20 at a
  /// time (logo, rating, genres: never one request per card), then searched, filtered and sorted.
  /// [titles]: every title (mine), or the pages read so far (a member's: [complete] once every page
  /// is read; [loadMore] reads the next one, [footer] under the grid).
  Widget _titles(
    BuildContext context,
    List<MediaItem> titles, {
    required bool mine,
    required Future<void> Function() onRefresh,
    bool complete = true,
    VoidCallback? loadMore,
    Widget? footer,
  }) {
    // An episode in the list counts for its series: once.
    final seen = <TitleRef>{};
    final unique = [
      for (final title in titles)
        if (seen.add((type: title.type, id: title.id))) title,
    ];

    final List<MediaItem> matching;
    final List<MediaItem> shown;
    final bool detailsLoading;
    if (_needsDetails) {
      // Genre, rating: the catalog's details of every title first (20 a request).
      final (ready, loading) = _details(unique);
      matching = _sorted(_matching(ready));
      shown = matching.take(_shown).toList();
      detailsLoading = loading;
    } else {
      // Type, years, text: the list's own data. The catalog's details of the titles shown only.
      matching = _sorted(_matching(unique));
      final (ready, loading) = _details(matching.take(_shown).toList());
      shown = [for (final item in ready) item.withDetails(_known[(type: item.type, id: item.id)])];
      detailsLoading = loading;
    }
    final more = detailsLoading || !complete || matching.length > shown.length;

    // Still reading: the first cards, or titles a search or a filter may match.
    if (shown.isEmpty && more) {
      return const Center(child: CircularProgressIndicator());
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
      child: PosterGrid(
        items: shown,
        alwaysScrollable: true,
        padding: pageContentPadding(context),
        // Near the end of the cards: 20 more (a member's next page when every title read is shown).
        onBuild: (i) {
          if (i < shown.length - NextPage.margin) return;
          // Not while the titles asked are still coming.
          if (shown.length >= _shown && (matching.length > _shown || !complete)) _nextTitles.request();
          if (!complete) loadMore?.call();
        },
        footer: detailsLoading ? const _MoreComing() : footer,
      ),
    );
  }

  /// The beginning of [titles] whose catalog details are read (or that the catalog doesn't know),
  /// and whether more are on their way. The details missing are asked 20 titles a request, one
  /// request after the other.
  (List<MediaItem>, bool) _details(List<MediaItem> titles) {
    final unknown = [
      for (final t in titles)
        if (!_known.containsKey((type: t.type, id: t.id))) (type: t.type, id: t.id),
    ];
    final answered = <TitleRef>{};
    var loading = false;
    for (var i = 0; i < unknown.length; i += pageSize) {
      final chunk = unknown.skip(i).take(pageSize).toList();
      final batch = ref.watch(titlesByIdProvider(titlesKey(chunk)));
      if (!batch.hasValue && !batch.hasError) {
        loading = true;
        break;
      }
      _known.addAll(batch.value ?? const {});
      answered.addAll(chunk);
    }
    final ready = <MediaItem>[];
    for (final t in titles) {
      final key = (type: t.type, id: t.id);
      if (!_known.containsKey(key) && !answered.contains(key)) break;
      ready.add(t);
    }
    return (ready, loading);
  }

  /// « Note », « Votants » and « Mieux notés »: the rating each card shows (IMDb's, given with the
  /// catalog's details, else TMDb's) and its voters, ranges checked like the API's.
  double? _ratingOf(MediaItem item) => item.shownRating?.$2.value;

  /// The titles that match the search and the filters, with what the catalog says of them.
  List<MediaItem> _matching(List<MediaItem> titles) {
    final found = <MediaItem>[];
    for (final title in titles) {
      final details = _known[(type: title.type, id: title.id)];
      final item = title.withDetails(details);
      if (_matches(item, details)) found.add(item);
    }
    return found;
  }

  bool _matches(MediaItem item, MediaItem? details) {
    if (_filters.kind.mediaType != null && item.type != _filters.kind.mediaType) return false;
    if (_query.isNotEmpty && !item.title.toLowerCase().contains(_query.toLowerCase())) return false;
    if (!_filters.yearWithin(item.year)) return false;
    if (!_filters.ratingWithin(_ratingOf(item), item.shownRating?.$2.votes ?? 0)) return false;
    if (_filters.genre != null && details != null && !details.genreIds.contains(_filters.genre!.id)) return false;
    return true;
  }

  List<MediaItem> _sorted(List<MediaItem> items) {
    switch (_filters.sortFor(withText: false)) {
      case SearchSort.rating:
        // Without any rating: last.
        items.sort((a, b) => (_ratingOf(b) ?? -1).compareTo(_ratingOf(a) ?? -1));
      case SearchSort.recent:
        items.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      case SearchSort.oldest:
        items.sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
      case SearchSort.relevance:
      case SearchSort.popularity:
        // Keep the list's own order (most recently added first).
        break;
    }
    return items;
  }
}

/// Under the grid while the next titles come.
class _MoreComing extends StatelessWidget {
  const _MoreComing();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator()),
  );
}
