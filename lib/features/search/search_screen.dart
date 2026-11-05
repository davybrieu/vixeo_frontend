import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/hero.dart';
import '../catalog/models.dart';
import '../catalog/person_screen.dart';
import '../catalog/widgets.dart';
import 'filter_bar.dart';
import 'search_filters.dart';

/// Recent searches of this app session (not synced yet).
final recentSearchesProvider = NotifierProvider<RecentSearches, List<String>>(RecentSearches.new);

class RecentSearches extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void add(String query) => state = [query, ...state.where((q) => q != query)].take(8).toList();

  void remove(String query) => state = state.where((q) => q != query).toList();

  void clear() => state = const [];
}

/// Search page. Without a text: "Explorer" (whole catalog by type, genre, years, rating and order),
/// with the trending carousel on a phone. With a text: the results, filtered and sorted the same
/// way. On larger screens, the hero (backdrop and information) follows the selected or hovered
/// result, as on the home page.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _hero = HeroSelection();
  Timer? _debounce;
  String _query = '';
  SearchFilters _filters = const SearchFilters();

  bool get _withText => _query.isNotEmpty;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _hero.dispose();
    super.dispose();
  }

  void _setQuery(String query) {
    if (query == _query) return;
    setState(() {
      _query = query;
      _filters = _filters.forText(withText: query.isNotEmpty);
    });
    // New results: the hero goes back to the first one.
    _hero.reset();
  }

  void _setFilters(SearchFilters filters) {
    setState(() => _filters = filters.forText(withText: _withText));
    _hero.reset();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = value.trim();
      if (q.length >= 2) ref.read(recentSearchesProvider.notifier).add(q);
      _setQuery(q.length >= 2 ? q : '');
    });
  }

  void _use(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _setQuery(query);
  }

  void _clear() {
    _controller.clear();
    _setQuery('');
  }

  /// First result, shown in the hero until a card is selected or hovered.
  MediaItem? _firstResult(bool Function(MediaType type) hasGenre) {
    final type = _filters.kind.mediaType;
    if (_filters.kind == SearchKind.person) return null;
    if (type != null) {
      return ref
          .watch(titlesProvider(TitleQuery(type, _filters, query: _withText ? _query : null)))
          .value
          ?.items
          .firstOrNull;
    }
    if (_withText) {
      final results = ref.watch(searchProvider((_query, _filters))).value;
      return results?.movies.firstOrNull ?? results?.shows.firstOrNull;
    }
    for (final type in MediaType.values) {
      if (!hasGenre(type)) continue;
      final first = ref.watch(titlesProvider(TitleQuery(type, _filters))).value?.items.firstOrNull;
      if (first != null) return first;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;

    // Explore with "Tout": a genre only movies (or only TV shows) have leaves the other type out.
    // Until the genres are loaded, both types are asked.
    final genres = ref.watch(allGenresProvider).value;
    bool hasGenre(MediaType type) =>
        _filters.genre == null || genres == null || (genres[type]?.contains(_filters.genre) ?? false);

    final header = Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 16 * s, layout.gutter, 12 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recherche', style: VxText.title(28 * s)),
          SizedBox(height: 16 * s),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.isPhone ? double.infinity : 720 * s),
            child: _SearchField(
              controller: _controller,
              autofocus: !layout.isPhone,
              fontSize: 16 * s,
              onChanged: _onChanged,
              onSubmitted: (v) {
                _debounce?.cancel();
                _onChanged(v);
              },
              onClear: _clear,
            ),
          ),
        ],
      ),
    );
    final filterBar = SearchFilterBar(filters: _filters, withText: _withText, onChanged: _setFilters);
    final results = _Results(
      query: _query,
      filters: _filters,
      hasGenre: hasGenre,
      onFocused: layout.isPhone ? null : _hero.select,
      onHovered: layout.isPhone ? null : _hero.hover,
      onPickRecent: _use,
      onResetFilters: () => _setFilters(const SearchFilters()),
    );

    if (layout.isPhone) {
      return SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            filterBar,
            const SizedBox(height: 12),
            Expanded(child: results),
          ],
        ),
      );
    }

    // Larger screens: the hero follows the selected or hovered result (first result meanwhile).
    final first = _firstResult(hasGenre);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: layout.tv(760),
          child: ValueListenableBuilder(
            valueListenable: _hero.item,
            builder: (_, selected, _) {
              final item = selected ?? first;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: item == null ? const SizedBox.expand() : HeroBackdrop(key: ValueKey(item.id), item: item),
              );
            },
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              filterBar,
              SizedBox(height: layout.tv(24)),
              ValueListenableBuilder(
                valueListenable: _hero.item,
                builder: (_, selected, _) {
                  final item = selected ?? first;
                  return item == null
                      ? const SizedBox.shrink()
                      : SizedBox(
                          height: layout.tv(320),
                          child: HeroText(item: item, compact: true),
                        );
                },
              ),
              Expanded(child: results),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.autofocus,
    required this.fontSize,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool autofocus;
  final double fontSize;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: color, width: width),
    );

    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (_, value, _) => TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: VxText.body(fontSize),
        decoration: InputDecoration(
          hintText: 'Films, séries, acteurs…',
          filled: true,
          fillColor: VxColors.background.withValues(alpha: 0.6),
          prefixIcon: const Icon(Icons.search_rounded, color: VxColors.textSecondary),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(tooltip: 'Effacer', icon: const Icon(Icons.close_rounded), onPressed: onClear),
          border: border(VxColors.line),
          enabledBorder: border(VxColors.line),
          focusedBorder: border(VxColors.accent, 2),
        ),
      ),
    );
  }
}

/// What is under the filters: explore (no text) or results, for the chosen type.
class _Results extends ConsumerWidget {
  const _Results({
    required this.query,
    required this.filters,
    required this.hasGenre,
    required this.onFocused,
    required this.onHovered,
    required this.onPickRecent,
    required this.onResetFilters,
  });

  final String query;
  final SearchFilters filters;
  final bool Function(MediaType type) hasGenre;
  final void Function(MediaItem item)? onFocused;
  final void Function(MediaItem item)? onHovered;
  final ValueChanged<String> onPickRecent;
  final VoidCallback onResetFilters;

  bool get _withText => query.isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final type = filters.kind.mediaType;

    final emptyMessage = _withText
        ? 'Rien ne correspond à « $query »${filters.hasTitleFilters ? ' avec ces filtres' : ''}.'
        : 'Aucun titre ne correspond à ces filtres.';

    final List<Widget> content;
    if (filters.kind == SearchKind.person) {
      content = [
        _PagedGrid<Person>(
          key: ValueKey(('people', query)),
          page: (page) => peopleProvider((query, page)),
          idOf: (p) => p.id,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: layout.isLarge ? layout.tv(220) : 110,
            mainAxisExtent: layout.isLarge ? layout.tv(260) : 140,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (_, person) => _PersonTile(person: person),
          empty: _Empty(title: 'Aucun résultat', message: emptyMessage),
        ),
      ];
    } else if (type != null) {
      final q = TitleQuery(type, filters, query: _withText ? query : null);
      final format = posterFormatOf(ref);
      content = [
        _PagedGrid<MediaItem>(
          key: ValueKey(q),
          page: (page) => titlesProvider(q.atPage(page)),
          idOf: (item) => item.id,
          gridDelegate: posterGridDelegate(layout, format),
          itemBuilder: (_, item) => LayoutBuilder(
            builder: (_, c) => PosterCard(
              item: item,
              width: c.maxWidth,
              format: format,
              onFocused: onFocused == null ? null : () => onFocused!(item),
              onHovered: onHovered == null ? null : () => onHovered!(item),
            ),
          ),
          empty: _Empty(
            title: 'Aucun résultat',
            message: emptyMessage,
            onReset: filters.isDefault ? null : onResetFilters,
          ),
        ),
      ];
    } else if (_withText) {
      content = [
        _SearchRows(
          query: query,
          filters: filters,
          onFocused: onFocused,
          onHovered: onHovered,
          empty: emptyMessage,
          onReset: filters.isDefault ? null : onResetFilters,
        ),
      ];
    } else {
      content = [
        _ExploreRows(
          filters: filters,
          hasGenre: hasGenre,
          onFocused: onFocused,
          onHovered: onHovered,
          onReset: onResetFilters,
        ),
      ];
    }

    return CustomScrollView(
      slivers: [
        if (!_withText) ...[
          _RecentSearches(onPick: onPickRecent),
          // Phone: trending titles of the chosen type, before typing (the large-screen hero
          // shows the first result instead).
          if (layout.isPhone) SliverToBoxAdapter(child: _TrendingCarousel(type: type)),
        ],
        ...content,
        SliverToBoxAdapter(child: SizedBox(height: layout.isLarge ? layout.tv(80) : 32)),
      ],
    );
  }
}

class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final recent = ref.watch(recentSearchesProvider);
    if (recent.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 20),
      sliver: SliverList.list(
        children: [
          Row(
            children: [
              Expanded(child: Text('Recherches récentes', style: VxText.title(17))),
              TextButton(
                onPressed: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: const Text('Effacer'),
              ),
            ],
          ),
          for (final q in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded, color: VxColors.textMuted),
              title: Text(q, style: VxText.body(15)),
              onTap: () => onPick(q),
              trailing: IconButton(
                tooltip: 'Retirer « $q » de l’historique',
                icon: const Icon(Icons.close_rounded, size: 18, color: VxColors.textMuted),
                onPressed: () => ref.read(recentSearchesProvider.notifier).remove(q),
              ),
            ),
        ],
      ),
    );
  }
}

/// Phone, before typing: the featured (trending) titles of the home, for the chosen type.
class _TrendingCarousel extends ConsumerWidget {
  const _TrendingCarousel({required this.type});

  final MediaType? type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(homeProvider(type)).value?.featured ?? const <MediaItem>[];
    if (featured.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: FeaturedCarousel(items: featured),
    );
  }
}

/// Explore with "Tout": a row of movies and a row of TV shows (choose a type to see all).
class _ExploreRows extends ConsumerWidget {
  const _ExploreRows({
    required this.filters,
    required this.hasGenre,
    required this.onFocused,
    required this.onHovered,
    required this.onReset,
  });

  final SearchFilters filters;
  final bool Function(MediaType type) hasGenre;
  final void Function(MediaItem item)? onFocused;
  final void Function(MediaItem item)? onHovered;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final types = MediaType.values.where(hasGenre).toList();
    final pages = {for (final type in types) type: ref.watch(titlesProvider(TitleQuery(type, filters)))};

    if (pages.values.any((p) => p.isLoading && !p.hasValue)) {
      return const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
    }
    final failed = pages.entries.where((e) => e.value.hasError).toList();
    if (failed.length == pages.length && failed.isNotEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorPanel(
          error: failed.first.value.error!,
          onRetry: () {
            for (final e in failed) {
              ref.invalidate(titlesProvider(TitleQuery(e.key, filters)));
            }
          },
        ),
      );
    }
    final rows = [
      for (final type in types)
        if (pages[type]?.value?.items case final items? when items.isNotEmpty)
          (type == MediaType.movie ? 'Films' : 'Séries', items),
    ];
    if (rows.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _Empty(
          title: 'Aucun titre',
          message: 'Aucun titre ne correspond à ces filtres.',
          onReset: filters.isDefault ? null : onReset,
        ),
      );
    }
    return SliverList.list(
      children: [
        for (final (index, (title, items)) in rows.indexed) ...[
          if (index > 0) SizedBox(height: layout.isLarge ? layout.tv(36) : 24),
          PosterRow(title: title, items: items, onFocused: onFocused, onHovered: onHovered),
        ],
      ],
    );
  }
}

/// Search with "Tout": rows of movies, TV shows and people.
class _SearchRows extends ConsumerWidget {
  const _SearchRows({
    required this.query,
    required this.filters,
    required this.onFocused,
    required this.onHovered,
    required this.empty,
    required this.onReset,
  });

  final String query;
  final SearchFilters filters;
  final void Function(MediaItem item)? onFocused;
  final void Function(MediaItem item)? onHovered;
  final String empty;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final key = (query, filters);
    final results = ref.watch(searchProvider(key));
    final gap = SizedBox(height: layout.isLarge ? layout.tv(36) : 24);

    return switch (results) {
      AsyncData(:final value) when value.isEmpty => SliverFillRemaining(
        hasScrollBody: false,
        child: _Empty(title: 'Aucun résultat', message: empty, onReset: onReset),
      ),
      AsyncData(:final value) => SliverList.list(
        children: [
          if (value.movies.isNotEmpty)
            PosterRow(title: 'Films', items: value.movies, onFocused: onFocused, onHovered: onHovered),
          if (value.shows.isNotEmpty) ...[
            if (value.movies.isNotEmpty) gap,
            PosterRow(title: 'Séries', items: value.shows, onFocused: onFocused, onHovered: onHovered),
          ],
          if (value.people.isNotEmpty) ...[
            if (value.movies.isNotEmpty || value.shows.isNotEmpty) gap,
            const SectionHeader('Personnes'),
            FocusTraversalGroup(
              child: SizedBox(
                height: layout.isLarge ? layout.tv(270) : 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                  itemCount: value.people.length,
                  separatorBuilder: (_, _) => SizedBox(width: layout.isLarge ? layout.tv(28) : 16),
                  itemBuilder: (_, i) => SizedBox(
                    width: layout.isLarge ? layout.tv(180) : 84,
                    child: _PersonTile(person: value.people[i]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      AsyncError(:final error) => SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorPanel(error: error, onRetry: () => ref.invalidate(searchProvider(key))),
      ),
      _ => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
    };
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.isLarge ? layout.tv(150) : 72.0;
    return VxFocusable(
      borderRadius: size / 2,
      semanticLabel: person.name,
      onPressed: () => context.push(personPath(person.id)),
      child: Column(
        children: [
          ClipOval(
            child: SizedBox.square(
              dimension: size,
              child: NetImage(
                url: person.profileUrl,
                seed: person.id,
                fallback: Center(child: Text(person.initials, style: VxText.title(size * 0.3))),
              ),
            ),
          ),
          SizedBox(height: layout.isLarge ? layout.tv(12) : 6),
          Text(
            person.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: VxText.body(layout.isLarge ? layout.tv(22) : 13, weight: FontWeight.w600, height: 1.2),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.message, this.onReset});

  final String title;
  final String message;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      EmptyState(icon: Icons.search_off_rounded, title: title, message: message),
      if (onReset != null)
        VxButton(label: 'Réinitialiser les filtres', kind: VxButtonKind.secondary, onPressed: onReset),
    ],
  );
}

/// Grid loading the next page when its end comes into view (scroll, or remote focus moving down).
class _PagedGrid<T> extends ConsumerStatefulWidget {
  const _PagedGrid({
    super.key,
    required this.page,
    required this.idOf,
    required this.gridDelegate,
    required this.itemBuilder,
    required this.empty,
  });

  final FutureProvider<Paged<T>> Function(int page) page;
  final Object Function(T item) idOf;
  final SliverGridDelegate gridDelegate;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget empty;

  @override
  ConsumerState<_PagedGrid<T>> createState() => _PagedGridState<T>();
}

class _PagedGridState<T> extends ConsumerState<_PagedGrid<T>> {
  int _pages = 1;
  bool _scheduled = false;

  void _loadMore(int next) {
    if (_scheduled || next <= _pages) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && next > _pages) setState(() => _pages = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final pages = [for (var p = 1; p <= _pages; p++) ref.watch(widget.page(p))];
    final first = pages.first;
    final last = pages.last;

    if (first.isLoading && !first.hasValue) {
      return const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
    }
    if (first.hasError && !first.hasValue) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorPanel(error: first.error!, onRetry: () => ref.invalidate(widget.page(1))),
      );
    }

    // TMDb pages can repeat a title: shown once.
    final seen = <Object>{};
    final items = [
      for (final page in pages)
        for (final item in page.value?.items ?? <T>[])
          if (seen.add(widget.idOf(item))) item,
    ];
    if (items.isEmpty && !(last.value?.hasMore ?? false)) {
      return SliverFillRemaining(hasScrollBody: false, child: widget.empty);
    }
    final next = last.value?.hasMore ?? false ? _pages + 1 : null;

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          // Room for the focus zoom on TV.
          padding: EdgeInsets.fromLTRB(layout.gutter, layout.isLarge ? layout.tv(16) : 0, layout.gutter, 0),
          sliver: SliverGrid.builder(
            gridDelegate: widget.gridDelegate,
            itemCount: items.length,
            itemBuilder: (context, i) {
              if (next != null && i >= items.length - 6) _loadMore(next);
              return widget.itemBuilder(context, items[i]);
            },
          ),
        ),
        if (last.isLoading && _pages > 1)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (last.hasError && _pages > 1)
          SliverToBoxAdapter(
            child: Center(
              child: TextButton(onPressed: () => ref.invalidate(widget.page(_pages)), child: const Text('Réessayer')),
            ),
          ),
      ],
    );
  }
}

/// Titles of one genre (older links to `/recherche/genre/...`; the search page filters by genre).
class GenreScreen extends ConsumerWidget {
  const GenreScreen({super.key, required this.type, required this.genreId, required this.name});

  final MediaType type;
  final int genreId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(discoverProvider((type, genreId)));
    return Scaffold(
      appBar: AppBar(
        title: Text(name, style: VxText.title(20)),
        backgroundColor: VxColors.background,
      ),
      body: AsyncView(
        value: items,
        onRetry: () => ref.invalidate(discoverProvider((type, genreId))),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.movie_filter_outlined, title: 'Aucun titre')
            : PosterGrid(items: list),
      ),
    );
  }
}
