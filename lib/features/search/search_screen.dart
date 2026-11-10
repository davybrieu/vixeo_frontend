import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/hero.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../tv/channel_row.dart';
import '../tv/channel_search.dart';
import 'filter_bar.dart';
import 'search_filters.dart';
import 'search_history.dart';

/// Search page. Without a text: "Explorer" (whole catalog by type, genre, years, rating and order).
/// With a text: the results, filtered and sorted the same way. On larger screens, the hero
/// (backdrop and information) follows the selected or hovered result, as on the home page; a
/// phone has no hero nor carousel here.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialType});

  final MediaType? initialType;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _hero = HeroSelection();
  Timer? _debounce;
  String _query = '';
  late SearchFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = SearchFilters(
      kind: switch (widget.initialType) {
        MediaType.movie => SearchKind.movie,
        MediaType.tv => SearchKind.tv,
        null => SearchKind.all,
      },
    );
  }

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
    });
    // New results: the hero goes back to the first one.
    _hero.reset();
  }

  void _setFilters(SearchFilters filters) {
    setState(() => _filters = filters);
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
    if (_filters.kind == SearchKind.person || _filters.kind.isChannels) return null;
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

    // Explore with "Tout": a genre only movies (or only TV shows) have leaves the other type out.
    // Until the genres are loaded, both types are asked.
    final genres = ref.watch(allGenresProvider).value;
    bool hasGenre(MediaType type) =>
        _filters.genre == null || genres == null || (genres[type]?.contains(_filters.genre) ?? false);

    final header = VxPageHeader(
      title: 'Recherche',
      search: VxSearchField(
        controller: _controller,
        autofocus: !layout.isPhone,
        fontSize: layout.size(16, tv: 24),
        onChanged: _onChanged,
        onSubmitted: (v) {
          _debounce?.cancel();
          _onChanged(v);
        },
        onClear: _clear,
      ),
      filters: SearchFilterBar(filters: _filters, withText: _withText, onChanged: _setFilters),
    );
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
              ValueListenableBuilder(
                valueListenable: _hero.item,
                builder: (_, selected, _) {
                  final item = selected ?? first;
                  return item == null
                      ? const SizedBox.shrink()
                      : SizedBox(
                          height: layout.tv(350),
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
    if (filters.kind.isChannels) {
      content = [ChannelSearchResults(query: query, categoryId: filters.category?.id)];
    } else if (filters.kind == SearchKind.person) {
      content = [
        _PagedGrid<Person>(
          key: ValueKey(('people', query)),
          page: (page) => peopleProvider((query, page)),
          idOf: (p) => p.id,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: PersonCard.widthOf(layout) * 1.1,
            mainAxisExtent: PersonCard.heightOf(layout, withRole: false),
            // A grid of cards: the same gaps as the poster grids.
            crossAxisSpacing: layout.cardGap,
            mainAxisSpacing: layout.cardGap,
          ),
          itemBuilder: (_, person) => Center(child: PersonCard(person: person)),
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
        if (!_withText && !filters.kind.isChannels) _RecentSearches(onPick: onPickRecent),
        ...content,
        // The end of the page clear of the tab bar.
        SliverToBoxAdapter(child: SizedBox(height: pageBottomPadding(context))),
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
    // Synced with the profile's other devices; the 8 most recent here.
    final recent = (ref.watch(recentSearchesProvider).value ?? const <RecentSearch>[]).take(8).toList();
    if (recent.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.sectionGap),
      sliver: NumberedSliverList(recent: recent, onPick: onPick),
    );
  }
}

class NumberedSliverList extends ConsumerWidget {
  const NumberedSliverList({super.key, required this.recent, required this.onPick});
  final List<RecentSearch> recent;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SliverList.list(
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
        for (final search in recent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history_rounded, color: VxColors.textMuted),
            title: Text(search.query, style: VxText.body(15)),
            onTap: () => onPick(search.query),
            trailing: IconButton(
              tooltip: 'Retirer « ${search.query} » de l’historique',
              icon: const Icon(Icons.close_rounded, size: 18, color: VxColors.textMuted),
              onPressed: () => ref.read(recentSearchesProvider.notifier).remove(search),
            ),
          ),
      ],
    );
  }
}

/// Explore with "Tout": a row of movies, a row of TV shows, then the live channels and popular
/// people, always there (choose a type to see all). A genre, years or rating filter keeps the
/// titles only: they don't apply to channels and people.
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
    final others = !filters.hasTitleFilters;
    if (rows.isEmpty && !others) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _Empty(
          title: 'Aucun titre',
          message: 'Aucun titre ne correspond à ces filtres.',
          onReset: filters.isDefault ? null : onReset,
        ),
      );
    }
    final gap = SizedBox(height: layout.sectionGap);
    return SliverList.list(
      children: [
        for (final (index, (title, items)) in rows.indexed) ...[
          if (index > 0) gap,
          PosterRow(title: title, items: items, onFocused: onFocused, onHovered: onHovered),
        ],
        if (others) ...[
          if (rows.isNotEmpty) gap,
          const _ChannelsSection(query: ''),
          gap,
          _PeopleSection(people: ref.watch(peopleProvider(('', 1))).whenData((p) => p.items), query: ''),
        ],
      ],
    );
  }
}

/// Search with "Tout": rows of movies and TV shows, then the live channels and the people, always
/// there. With a genre, years or rating filter, the titles only (the API returns no people).
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
    final gap = SizedBox(height: layout.sectionGap);

    final others = !filters.hasTitleFilters;

    return switch (results) {
      AsyncData(:final value) when value.isEmpty && !others => SliverFillRemaining(
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
          if (others) ...[
            if (value.movies.isNotEmpty || value.shows.isNotEmpty) gap,
            _ChannelsSection(query: query),
            gap,
            _PeopleSection(people: AsyncData(value.people), query: query),
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

/// « Chaînes TV » of "Tout": the channels matching the text (all without one), in the home
/// page's row. Always there, with a short line when there is none.
class _ChannelsSection extends ConsumerWidget {
  const _ChannelsSection({required this.query});

  final String query;

  /// A row, not the whole list: « Chaînes TV » shows them all.
  static const _rowLimit = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelSearchProvider((query, null)));
    return switch (channels) {
      AsyncData(:final value) when value.isNotEmpty => ChannelRow(channels: value.take(_rowLimit).toList()),
      AsyncData() => _SectionNote(
        title: 'Chaînes TV',
        message: query.isEmpty
            ? 'Aucune chaîne disponible pour le moment.'
            : 'Aucune chaîne ne correspond à « $query ».',
      ),
      AsyncError(:final error) => _SectionNote(title: 'Chaînes TV', message: _errorText(error)),
      _ => const _SectionNote(title: 'Chaînes TV', message: 'Chargement des chaînes…'),
    };
  }
}

/// « Personnes » of "Tout": the people matching the text, or the popular ones without a text.
/// Always there, with a short line when there is none.
class _PeopleSection extends StatelessWidget {
  const _PeopleSection({required this.people, required this.query});

  final AsyncValue<List<Person>> people;
  final String query;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return switch (people) {
      AsyncData(:final value) when value.isNotEmpty => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Personnes'),
          FocusTraversalGroup(
            child: SizedBox(
              height: PersonCard.heightOf(layout, withRole: false) + (layout.isLarge ? layout.tv(32) : 0),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.isLarge ? layout.tv(16) : 0),
                itemCount: value.length,
                separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
                itemBuilder: (_, i) => PersonCard(person: value[i]),
              ),
            ),
          ),
        ],
      ),
      AsyncData() => _SectionNote(
        title: 'Personnes',
        message: query.isEmpty ? 'Aucune personne à afficher.' : 'Aucune personne ne correspond à « $query ».',
      ),
      AsyncError(:final error) => _SectionNote(title: 'Personnes', message: _errorText(error)),
      _ => const _SectionNote(title: 'Personnes', message: 'Chargement des personnes…'),
    };
  }
}

/// The API's French message, or a generic one.
String _errorText(Object error) => error is ApiException ? error.message : 'Une erreur est survenue.';

/// A section title with a short line under it (nothing to show, or not loaded yet).
class _SectionNote extends StatelessWidget {
  const _SectionNote({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: Text(message, style: VxText.body(layout.size(14, tv: 22), color: VxColors.textMuted)),
        ),
      ],
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
