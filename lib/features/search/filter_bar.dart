import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/range_slider.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../tv/models.dart';
import '../tv/tv_repository.dart';
import 'search_filters.dart';

/// [filters] with another type: a genre the type doesn't have (e.g. "Horreur" for TV shows) is
/// dropped, and the channel category only stays for channels. The type chips and the « Voir tout »
/// buttons of the search's "Tout" both go through it.
SearchFilters filtersOfKind(SearchFilters filters, SearchKind kind, Map<MediaType, List<Genre>>? genres) {
  final keepGenre = filters.genre == null || genres == null || genresFor(kind, genres).contains(filters.genre);
  return filters.copyWith(
    kind: kind,
    genre: keepGenre ? null : () => null,
    category: kind.isChannels ? null : () => null,
  );
}

/// Genres offered for a type filter: movie or TV genres, or both for "Tout" (TMDb ids differ
/// between the two lists for some genres, e.g. "Action" and "Action & Adventure").
List<Genre> genresFor(SearchKind kind, Map<MediaType, List<Genre>> all) {
  final type = kind.mediaType;
  if (type != null) return all[type] ?? const [];
  final union = <Genre>{...?all[MediaType.movie], ...?all[MediaType.tv]}.toList();
  return union..sort((a, b) => _fold(a.name).compareTo(_fold(b.name)));
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c');

/// Type, genre, years and order of the search page, in one scrollable row of chips. Genre, years
/// and order don't apply to people or live channels: hidden for those kinds. Live channels have
/// their « Catégorie » instead, the same kind of chip as « Genre ». [withRating] adds « Note »,
/// « Votants » and « Mieux notés », on the rating each card shows (IMDb's, else TMDb's) and its
/// voters: the search page asks the API, « À voir » applies them itself.
class SearchFilterBar extends ConsumerWidget {
  const SearchFilterBar({
    super.key,
    required this.filters,
    required this.withText,
    required this.onChanged,
    this.kinds = SearchKind.values,
    this.channelCategories = true,
    this.withRating = false,
  });

  /// Types offered (« À voir » has no people).
  final List<SearchKind> kinds;

  /// « Catégorie » for live channels (the search page; not « À voir »).
  final bool channelCategories;

  /// « Note » and « Votants » filters, « Mieux notés » order (search page, « À voir »).
  final bool withRating;

  final SearchFilters filters;

  /// A text is typed: "Pertinence" is offered.
  final bool withText;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final gap = FilterBar.gapOf(layout);
    final genres = ref.watch(allGenresProvider).value;
    // Every type always offered on the search page: « Chaînes TV » and « Personnes » too, with or
    // without a text.
    final withCategory = channelCategories && filters.kind.isChannels;
    final categories = withCategory ? ref.watch(tvCategoriesProvider).value : null;
    final order = filters.sortFor(withText: withText);

    void setKind(SearchKind kind) => onChanged(filtersOfKind(filters, kind, genres));

    Future<void> pickCategory() async {
      if (categories == null) return;
      final choice = await showVxChoice<TvCategory>(
        context,
        title: 'Catégorie',
        selected: filters.category,
        options: [(null, 'Toutes les catégories'), for (final c in categories) (c, c.name)],
      );
      if (choice != null) onChanged(filters.copyWith(category: () => choice.$1));
    }

    Future<void> pickGenre() async {
      if (genres == null) return;
      final choice = await showVxChoice<Genre>(
        context,
        title: 'Genre',
        selected: filters.genre,
        options: [(null, 'Tous les genres'), for (final g in genresFor(filters.kind, genres)) (g, g.name)],
      );
      if (choice != null) onChanged(filters.copyWith(genre: () => choice.$1));
    }

    Future<void> pickYears() async {
      final range = await pickYearRange(context, from: filters.yearFrom, to: filters.yearTo);
      if (range != null) onChanged(filters.copyWith(yearFrom: () => range.$1, yearTo: () => range.$2));
    }

    Future<void> pickRating() async {
      final range = await pickRatingRange(context, title: 'Note', min: filters.minRating, max: filters.maxRating);
      if (range != null) onChanged(filters.copyWith(minRating: () => range.$1, maxRating: () => range.$2));
    }

    Future<void> pickVotes() async {
      final range = await pickVotesRange(context, min: filters.minVotes, max: filters.maxVotes);
      if (range != null) onChanged(filters.copyWith(minVotes: () => range.$1, maxVotes: () => range.$2));
    }

    Future<void> pickSort() async {
      final choice = await showVxChoice<SearchSort>(
        context,
        title: 'Trier par',
        selected: order,
        options: [
          for (final s in SearchSort.available(withText: withText, withRating: withRating)) (s, s.label),
        ],
      );
      if (choice != null) onChanged(filters.copyWith(sort: () => choice.$1));
    }

    final titles = filters.kind != SearchKind.person && filters.kind != SearchKind.accounts && !filters.kind.isChannels;

    return FilterBar(
      child: Row(
        children: [
          for (final kind in kinds) ...[
            FilterChipButton(label: kind.label, selected: filters.kind == kind, onPressed: () => setKind(kind)),
            SizedBox(width: gap),
          ],
          if (titles) ...[
            Container(
              width: 1,
              height: layout.isLarge ? layout.tv(40) : 24,
              margin: EdgeInsets.only(right: gap),
              color: VxColors.lineStrong,
            ),
            FilterChipButton(
              label: filters.genre?.name ?? 'Genre',
              semanticLabel: 'Genre : ${filters.genre?.name ?? 'tous'}',
              selected: filters.genre != null,
              dropdown: true,
              onPressed: genres == null ? null : pickGenre,
            ),
            SizedBox(width: gap),
            FilterChipButton(
              label: yearRangeLabel(filters.yearFrom, filters.yearTo) ?? 'Années',
              semanticLabel: 'Années : ${yearRangeLabel(filters.yearFrom, filters.yearTo) ?? 'toutes'}',
              selected: filters.hasYears,
              dropdown: true,
              onPressed: pickYears,
            ),
            SizedBox(width: gap),
            if (withRating) ...[
              FilterChipButton(
                label: ratingRangeLabel(filters.minRating, filters.maxRating) ?? 'Note',
                semanticLabel: ratingRangeLabel(filters.minRating, filters.maxRating) ?? 'Note : toutes',
                selected: filters.minRating != null || filters.maxRating != null,
                dropdown: true,
                onPressed: pickRating,
              ),
              SizedBox(width: gap),
              FilterChipButton(
                label: votesRangeLabel(filters.minVotes, filters.maxVotes) ?? 'Votants',
                semanticLabel: votesRangeLabel(filters.minVotes, filters.maxVotes) ?? 'Votants : tous',
                selected: filters.minVotes != null || filters.maxVotes != null,
                dropdown: true,
                onPressed: pickVotes,
              ),
              SizedBox(width: gap),
            ],
            FilterChipButton(
              label: 'Tri : ${order.label}',
              semanticLabel: 'Trier par : ${order.label}',
              selected: filters.sort != null && order != filters.copyWith(sort: () => null).sortFor(withText: withText),
              dropdown: true,
              icon: Icons.swap_vert_rounded,
              onPressed: pickSort,
            ),
            SizedBox(width: gap),
          ],
          if (withCategory) ...[
            Container(
              width: 1,
              height: layout.isLarge ? layout.tv(40) : 24,
              margin: EdgeInsets.only(right: gap),
              color: VxColors.lineStrong,
            ),
            FilterChipButton(
              label: filters.category?.name ?? 'Catégorie',
              semanticLabel: 'Catégorie : ${filters.category?.name ?? 'toutes'}',
              selected: filters.category != null,
              dropdown: true,
              onPressed: categories == null || categories.isEmpty ? null : pickCategory,
            ),
            SizedBox(width: gap),
          ],
          if (!filters.isDefault)
            FilterChipButton(
              label: 'Réinitialiser',
              icon: Icons.close_rounded,
              outlined: false,
              onPressed: () => onChanged(const SearchFilters()),
            ),
        ],
      ),
    );
  }
}

/// « Années » with a two-thumb slider (1900 to this year, developer's request, 21/11/2026): the
/// first and last years chosen (null: no limit), or null when closed without applying.
Future<(int?, int?)?> pickYearRange(BuildContext context, {required int? from, required int? to}) async {
  final stops = RangeStops.years();
  final picked = await showVxRange(
    context,
    title: 'Années',
    count: stops.count,
    selected: stops.indexesOf(from, to),
    valueLabel: (i) => '${stops.values[i]}',
    summary: (start, end) {
      final (from, to) = stops.valuesAt((start, end));
      return yearRangeLabel(from, to) ?? 'Toutes les années';
    },
  );
  return picked == null ? null : stops.valuesAt(picked);
}

/// A rating range with a two-thumb slider (0 to 10 by half points): « Note » of the search and of
/// « Mes avis ». Null when closed without applying.
Future<(double?, double?)?> pickRatingRange(
  BuildContext context, {
  required String title,
  required double? min,
  required double? max,
}) async {
  const stops = RangeStops.ratings;
  final picked = await showVxRange(
    context,
    title: title,
    count: stops.count,
    selected: stops.indexesOf(min, max),
    valueLabel: (i) => formatRatingBound(stops.values[i]),
    summary: (start, end) {
      final (min, max) = stops.valuesAt((start, end));
      return ratingRangeLabel(min, max) ?? 'Toutes les notes';
    },
  );
  return picked == null ? null : stops.valuesAt(picked);
}

/// « Votants » with a two-thumb slider (0 to 1 000 000 and more): voters of the rating shown
/// (IMDb's, else TMDb's). Null when closed without applying.
Future<(int?, int?)?> pickVotesRange(BuildContext context, {required int? min, required int? max}) async {
  const stops = RangeStops.votes;
  final picked = await showVxRange(
    context,
    title: 'Votants',
    count: stops.count,
    selected: stops.indexesOf(min, max),
    valueLabel: (i) => '${formatCount(stops.values[i])}${i == stops.count - 1 ? '+' : ''}',
    summary: (start, end) {
      final (min, max) = stops.valuesAt((start, end));
      return votesRangeLabel(min, max) ?? 'Sans limite de votants';
    },
  );
  return picked == null ? null : stops.valuesAt(picked);
}

/// Row of filter chips under a page header (Recherche, À voir, Avis): scrolls sideways, with the
/// page's side margins and room for the focus zoom on TV (docs/charte-graphique.md).
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.child});

  final Widget child;

  /// Between two chips: 8 on phones, 14 on TV.
  static double gapOf(Layout layout) => layout.size(8, tv: 14);

  /// A row of chips, [gapOf] apart.
  static Widget chips(Layout layout, List<Widget> chips) => Row(
    children: [
      for (final (i, chip) in chips.indexed) ...[if (i > 0) SizedBox(width: gapOf(layout)), chip],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return FocusTraversalGroup(
      policy: vxTraversalPolicy,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.size(4, tv: 10)),
        child: child,
      ),
    );
  }
}

/// Chip of the filter bar: selected = green tint; [dropdown] adds an arrow (opens a list).
class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.selected = false,
    this.dropdown = false,
    this.outlined = true,
    this.icon,
  });

  final String label;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final bool selected;
  final bool dropdown;
  final bool outlined;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final large = layout.isLarge;
    final height = large ? layout.tv(60) : 36.0;
    final color = selected ? VxColors.accent : (onPressed == null ? VxColors.textMuted : VxColors.text);
    final iconSize = large ? layout.tv(28) : 18.0;

    return Semantics(
      selected: selected,
      child: VxFocusable(
        borderRadius: height / 2,
        semanticLabel: semanticLabel ?? label,
        onPressed: onPressed ?? () {},
        // The label above is read once (not twice with the text below).
        child: ExcludeSemantics(
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: large ? layout.tv(26) : 14),
            decoration: BoxDecoration(
              color: selected ? VxColors.accent.withValues(alpha: 0.14) : Colors.transparent,
              border: selected || !outlined ? null : Border.all(color: VxColors.lineStrong),
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: iconSize, color: color),
                  SizedBox(width: large ? layout.tv(8) : 6),
                ],
                Text(
                  label,
                  style: VxText.body(
                    large ? layout.tv(24) : 14,
                    weight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
                if (dropdown) ...[
                  SizedBox(width: large ? layout.tv(4) : 2),
                  Icon(Icons.expand_more_rounded, size: iconSize, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
