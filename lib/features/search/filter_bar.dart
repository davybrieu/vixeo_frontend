import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'search_filters.dart';

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

/// Type, genre, years, rating and order of the search page, in one scrollable row of chips.
/// Genre, years, rating and order don't apply to people or live channels: hidden for those kinds.
class SearchFilterBar extends ConsumerWidget {
  const SearchFilterBar({super.key, required this.filters, required this.withText, required this.onChanged});

  final SearchFilters filters;

  /// A text is typed: "Personnes" and "Pertinence" are offered.
  final bool withText;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final gap = layout.isLarge ? layout.tv(14) : 8.0;
    final genres = ref.watch(allGenresProvider).value;
    // Channels always available; people only with a text.
    final kinds = withText
        ? SearchKind.values
        : SearchKind.values.where((k) => k != SearchKind.person);
    final order = filters.sortFor(withText: withText);

    void setKind(SearchKind kind) {
      // A genre the new type doesn't have (e.g. "Horreur" for TV shows) is dropped.
      final keepGenre = filters.genre == null || genres == null || genresFor(kind, genres).contains(filters.genre);
      onChanged(filters.copyWith(kind: kind, genre: keepGenre ? null : () => null));
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

    Future<void> pickDecade() async {
      final choice = await showVxChoice<Decade>(
        context,
        title: 'Années',
        selected: filters.decade,
        options: [(null, 'Toutes les années'), for (final d in Decade.values) (d, d.label)],
      );
      if (choice != null) onChanged(filters.copyWith(decade: () => choice.$1));
    }

    Future<void> pickRating() async {
      final choice = await showVxChoice<int>(
        context,
        title: 'Note minimale',
        selected: filters.minRating,
        options: [(null, 'Toutes les notes'), for (final r in SearchFilters.ratings) (r, '$r et plus')],
      );
      if (choice != null) onChanged(filters.copyWith(minRating: () => choice.$1));
    }

    Future<void> pickSort() async {
      final choice = await showVxChoice<SearchSort>(
        context,
        title: 'Trier par',
        selected: order,
        options: [for (final s in SearchSort.available(withText: withText)) (s, s.label)],
      );
      if (choice != null) onChanged(filters.copyWith(sort: () => choice.$1));
    }

    final titles = filters.kind != SearchKind.person && !filters.kind.isChannels;

    return FocusTraversalGroup(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.isLarge ? layout.tv(10) : 4),
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
                label: filters.decade?.label ?? 'Années',
                semanticLabel: 'Années : ${filters.decade?.label ?? 'toutes'}',
                selected: filters.decade != null,
                dropdown: true,
                onPressed: pickDecade,
              ),
              SizedBox(width: gap),
              FilterChipButton(
                label: filters.minRating == null ? 'Note' : 'Note ${filters.minRating}+',
                semanticLabel:
                    'Note minimale : ${filters.minRating == null ? 'toutes' : '${filters.minRating} et plus'}',
                selected: filters.minRating != null,
                dropdown: true,
                onPressed: pickRating,
              ),
              SizedBox(width: gap),
              FilterChipButton(
                label: 'Tri : ${order.label}',
                semanticLabel: 'Trier par : ${order.label}',
                selected:
                    filters.sort != null && order != filters.copyWith(sort: () => null).sortFor(withText: withText),
                dropdown: true,
                icon: Icons.swap_vert_rounded,
                onPressed: pickSort,
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
