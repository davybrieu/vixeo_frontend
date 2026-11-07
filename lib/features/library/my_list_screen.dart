import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../search/filter_bar.dart';
import '../search/search_filters.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setFilters(SearchFilters filters) {
    setState(() => _filters = filters.forText(withText: _query.isNotEmpty));
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final library = ref.watch(libraryProvider);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 16 * s, layout.gutter, 4 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ma liste', style: VxText.title(28 * s)),
                SizedBox(height: 16 * s),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: layout.isPhone ? double.infinity : 720 * s),
                  child: ValueListenableBuilder(
                    valueListenable: _searchController,
                    builder: (_, value, _) => TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      style: VxText.body(16 * s),
                      onChanged: (value) {
                        final query = value.trim();
                        setState(() {
                          _query = query;
                          _filters = _filters.forText(withText: query.isNotEmpty);
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Films, séries, acteurs…',
                        filled: true,
                        fillColor: VxColors.background.withValues(alpha: 0.6),
                        prefixIcon: const Icon(Icons.search_rounded, color: VxColors.textSecondary),
                        suffixIcon: value.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Effacer',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _query = '';
                                    _filters = _filters.forText(withText: false);
                                  });
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: const BorderSide(color: VxColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: const BorderSide(color: VxColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: const BorderSide(color: VxColors.accent, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SearchFilterBar(
            filters: _filters,
            withText: _query.isNotEmpty,
            onChanged: _setFilters,
          ),
          Expanded(
            child: AsyncView(
              value: library,
              onRetry: () => ref.invalidate(libraryProvider),
              data: (state) {
                final matching = <({ProfileItem favorite, MediaItem item, double rating, int? year})>[];

                for (final favorite in state.favorites) {
                  final title = favorite.tmdbTitle;
                  if (title == null) continue;
                  if (_filters.kind.mediaType != null && title.type != _filters.kind.mediaType) continue;
                  if (_query.isNotEmpty && !favorite.title.toLowerCase().contains(_query.toLowerCase())) continue;

                  final details = ref.watch(titleProvider((title.type, title.id))).value;
                  final year = details?.year ?? favorite.year;
                  final rating = details?.voteAverage ?? 0;

                  final decade = _filters.decade;
                  if (decade != null && year != null &&
                      (year < (decade.from ?? 0) || year > decade.to)) {
                    continue;
                  }
                  if (_filters.minRating != null && details != null && rating < _filters.minRating!) {
                    continue;
                  }
                  if (_filters.genre != null && details != null &&
                      !details.genres.contains(_filters.genre)) {
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
                    ),
                    rating: rating,
                    year: year,
                  ));
                }

                switch (_filters.sortFor(withText: _query.isNotEmpty)) {
                  case SearchSort.rating:
                    matching.sort((a, b) => b.rating.compareTo(a.rating));
                  case SearchSort.recent:
                    matching.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
                  case SearchSort.oldest:
                    matching.sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
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
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(layout.gutter),
                    gridDelegate: posterGridDelegate(layout, posterFormatOf(ref)),
                    itemCount: items.length,
                    itemBuilder: (context, i) => LayoutBuilder(
                      builder: (context, constraints) => PosterCard(
                        item: items[i],
                        width: constraints.maxWidth,
                        format: posterFormatOf(ref),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
