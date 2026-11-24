import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/models.dart' show Paged;
import '../catalog/paging.dart';
import '../catalog/widgets.dart' show titlePath;
import '../search/filter_bar.dart';
import '../search/search_filters.dart' show ratingRangeLabel, yearRangeLabel;
import '../social/review_likes.dart';
import '../social/social_repository.dart' show socialReviewsProvider;
import 'rating_form.dart';
import 'review_screen.dart';
import 'tmdb.dart';

/// Order of « Mes avis » / « Ses avis ».
enum ReviewSort {
  recent('Plus récents'),
  oldest('Plus anciens'),
  best('Meilleures notes'),
  worst('Moins bonnes notes'),
  title('Titre (A à Z)');

  const ReviewSort(this.label);

  final String label;
}

/// "Mes avis" (`/avis`, opened from the profile page): the profile's ratings and comments. With [username], « Ses avis »: another member's reviews (their profile page,
/// `/membre/:username/reviews`), read only. A search field (title, episode, comment) and, as on the
/// search page, filters (Tout by default, Films, Séries, Épisodes, years, rating) and an order (the
/// most recent first by default). Each of my reviews opens « Mon avis » (`ReviewScreen`), where it
/// is changed or removed: no button on the list; a member's opens the title.
class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key, this.username});

  /// A member's reviews; null: mine.
  final String? username;

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  final _search = TextEditingController();
  String _query = '';

  /// Null: every type ("Tout").
  RatedType? _type;

  /// « Années » and « Note » (of the review): ranges chosen with two-thumb sliders, like the search.
  int? _yearFrom;
  int? _yearTo;
  double? _minRating;
  double? _maxRating;
  ReviewSort _sort = ReviewSort.recent;

  bool get _hasYears => _yearFrom != null || _yearTo != null;
  bool get _hasRating => _minRating != null || _maxRating != null;
  bool get _filtered => _type != null || _hasYears || _hasRating || _sort != ReviewSort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickYears() async {
    final range = await pickYearRange(context, from: _yearFrom, to: _yearTo);
    if (range == null) return;
    setState(() {
      _yearFrom = range.$1;
      _yearTo = range.$2;
    });
  }

  Future<void> _pickRating() async {
    final range = await pickRatingRange(context, title: 'Note de l’avis', min: _minRating, max: _maxRating);
    if (range == null) return;
    setState(() {
      _minRating = range.$1;
      _maxRating = range.$2;
    });
  }

  Future<void> _pickSort() async {
    final choice = await showVxChoice<ReviewSort>(
      context,
      title: 'Trier par',
      selected: _sort,
      options: [for (final s in ReviewSort.values) (s, s.label)],
    );
    if (choice != null) setState(() => _sort = choice.$1 ?? ReviewSort.recent);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final member = widget.username;
    final filters = _ReviewFilters(
      type: _type,
      query: _query,
      yearFrom: _yearFrom,
      yearTo: _yearTo,
      minRating: _minRating,
      maxRating: _maxRating,
      sort: _sort,
    );

    // 20 reviews at a time, the next ones as the list scrolls. Mine: the API filters the type and
    // applies the order (except by title). What the API doesn't apply (a member's filters, the text,
    // years, rating, order by title) is applied here, on every page (one request after the other).
    final FutureProvider<Paged<RatedItem>> Function(int page) page;
    final bool here;
    if (member != null) {
      page = (number) => socialReviewsProvider((member, number));
      here = _filtered || _query.trim().isNotEmpty;
    } else {
      final order = switch (_sort) {
        ReviewSort.oldest => RatedOrder.oldest,
        ReviewSort.best => RatedOrder.highest,
        ReviewSort.worst => RatedOrder.lowest,
        ReviewSort.recent || ReviewSort.title => RatedOrder.recent,
      };
      page = (number) => myReviewsProvider((type: _type, order: order, page: number));
      here = _query.trim().isNotEmpty || _hasYears || _hasRating || _sort == ReviewSort.title;
    }
    final body = PagedBuilder<RatedItem>(
      // Another type or order asked to the API: from its first page.
      key: ValueKey(member == null ? (_type, _sort == ReviewSort.title ? ReviewSort.recent : _sort) : member),
      page: page,
      all: here,
      builder: (context, pages, nearEnd) => _ReviewsList(
        pages: pages,
        page: page,
        nearEnd: nearEnd,
        filters: filters,
        // Mine: already in the API's order, except by title.
        sortHere: member != null || _sort == ReviewSort.title,
        mine: member == null,
        onRefresh: () async {
          for (var p = 1; p <= pages.loaded; p++) {
            ref.invalidate(page(p));
          }
          await ref.read(page(1).future);
        },
      ),
    );

    final gap = FilterBar.gapOf(layout);
    final divider = Container(
      width: 1,
      height: layout.isLarge ? layout.tv(40) : 24,
      margin: EdgeInsets.only(right: gap),
      color: VxColors.lineStrong,
    );

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VxPageHeader(
            title: member == null ? 'Mes avis' : 'Ses avis',
            // Opened from a profile page: a way back.
            back: GoRouter.maybeOf(context)?.canPop() ?? false,
            search: VxSearchField(
              controller: _search,
              autofocus: !layout.isPhone,
              fontSize: layout.size(16, tv: 24),
              hintText: 'Titre, épisode, commentaire…',
              onChanged: (value) => setState(() => _query = value),
              onClear: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
            filters: FilterBar(
              child: Row(
                children: [
                  for (final type in <RatedType?>[null, ...RatedType.values]) ...[
                    FilterChipButton(
                      label: type?.label ?? 'Tout',
                      selected: type == _type,
                      semanticLabel: '${type?.label ?? 'Tout'}${type == _type ? ', sélectionné' : ''}',
                      onPressed: () => setState(() => _type = type),
                    ),
                    SizedBox(width: gap),
                  ],
                  divider,
                  FilterChipButton(
                    label: yearRangeLabel(_yearFrom, _yearTo) ?? 'Années',
                    semanticLabel: 'Années : ${yearRangeLabel(_yearFrom, _yearTo) ?? 'toutes'}',
                    selected: _hasYears,
                    dropdown: true,
                    onPressed: _pickYears,
                  ),
                  SizedBox(width: gap),
                  FilterChipButton(
                    label: ratingRangeLabel(_minRating, _maxRating) ?? 'Note',
                    semanticLabel: 'Note de l’avis : ${ratingRangeLabel(_minRating, _maxRating) ?? 'toutes'}',
                    selected: _hasRating,
                    dropdown: true,
                    onPressed: _pickRating,
                  ),
                  SizedBox(width: gap),
                  FilterChipButton(
                    label: 'Tri : ${_sort.label}',
                    semanticLabel: 'Trier par : ${_sort.label}',
                    selected: _sort != ReviewSort.recent,
                    dropdown: true,
                    icon: Icons.swap_vert_rounded,
                    onPressed: _pickSort,
                  ),
                  if (_filtered) ...[
                    SizedBox(width: gap),
                    FilterChipButton(
                      label: 'Réinitialiser',
                      icon: Icons.close_rounded,
                      onPressed: () => setState(() {
                        _type = null;
                        _yearFrom = null;
                        _yearTo = null;
                        _minRating = null;
                        _maxRating = null;
                        _sort = ReviewSort.recent;
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// What « Mes avis » / « Ses avis » shows: type, search, years, rating and order.
class _ReviewFilters {
  const _ReviewFilters({
    required this.type,
    required this.query,
    required this.yearFrom,
    required this.yearTo,
    required this.minRating,
    required this.maxRating,
    required this.sort,
  });

  final RatedType? type;
  final String query;
  final int? yearFrom;
  final int? yearTo;
  final double? minRating;
  final double? maxRating;
  final ReviewSort sort;

  bool matches(RatedItem item) {
    if (type != null && item.type != type) return false;
    if (!item.matches(query)) return false;
    final year = item.year;
    if (yearFrom != null || yearTo != null) {
      if (year == null || year < (yearFrom ?? year) || year > (yearTo ?? year)) return false;
    }
    if (minRating != null && item.value < minRating!) return false;
    if (maxRating != null && item.value > maxRating!) return false;
    return true;
  }

  /// [items] (the most recently rated first, as the API gives them) in this
  /// order. Equal ratings stay the most recent first.
  List<RatedItem> sorted(List<RatedItem> items) {
    final rank = {for (final (i, item) in items.indexed) item: i};
    int byRank(RatedItem a, RatedItem b) => rank[a]!.compareTo(rank[b]!);
    return switch (sort) {
      ReviewSort.recent => items,
      ReviewSort.oldest => items.reversed.toList(),
      ReviewSort.best => [...items]..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : byRank(a, b)),
      ReviewSort.worst => [...items]..sort((a, b) => a.value != b.value ? a.value.compareTo(b.value) : byRank(a, b)),
      ReviewSort.title => [...items]..sort((a, b) => foldForSearch(a.label).compareTo(foldForSearch(b.label))),
    };
  }
}

class _ReviewsList extends StatelessWidget {
  const _ReviewsList({
    required this.pages,
    required this.page,
    required this.nearEnd,
    required this.filters,
    required this.sortHere,
    required this.mine,
    required this.onRefresh,
  });

  final PagedItems<RatedItem> pages;
  final FutureProvider<Paged<RatedItem>> Function(int page) page;
  final void Function(int index, int count) nearEnd;
  final _ReviewFilters filters;

  /// The order is applied here (not by the API).
  final bool sortHere;
  final bool mine;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    if (pages.error case final error?) return ErrorPanel(error: error, onRetry: onRefresh);
    if (pages.loaded == 0) return const Center(child: CircularProgressIndicator());

    final all = pages.items;
    final matching = [
      for (final item in all)
        if (filters.matches(item)) item,
    ];
    final items = sortHere ? filters.sorted(matching) : matching;
    if (items.isEmpty) {
      // Still reading: the next pages may have some.
      if (!pages.complete) return const Center(child: CircularProgressIndicator());
      return EmptyState(
        icon: Icons.rate_review_outlined,
        title: all.isEmpty ? 'Aucun avis' : 'Aucun résultat',
        message: all.isEmpty
            ? (mine
                  ? 'Notez un film, une série ou un épisode depuis sa fiche : votre avis apparaîtra ici.'
                  : 'Aucun avis pour l’instant.')
            : 'Aucun ${mine ? 'de vos avis' : 'de ses avis'} ne correspond à cette recherche ou à ces filtres.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.size(900, tv: 1500)),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: pageContentPadding(context),
            // The reviews, then the next page coming (or « Réessayer »).
            itemCount: items.length + 1,
            separatorBuilder: (_, _) => SizedBox(height: layout.space(VxSpace.s)),
            itemBuilder: (_, i) {
              if (i == items.length) return PagedFooter(pages: pages, page: page);
              nearEnd(i, items.length);
              return ReviewRow(item: items[i], mine: mine);
            },
          ),
        ),
      ),
    );
  }
}

/// One review: image, title, its stars and the comment. One of mine opens « Mon avis »
/// (`ReviewScreen`), where it is changed or removed; another member's opens the title.
class ReviewRow extends StatelessWidget {
  const ReviewRow({super.key, required this.item, this.mine = true});

  final RatedItem item;

  /// A review of the active profile (« Mes avis »), not of another member (their profile page).
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final episode = item.type == RatedType.episode;
    final caption = layout.captionSize;
    final imageWidth = layout.size(episode ? 112 : 64, tv: episode ? 200 : 112);
    final imageHeight = episode ? imageWidth * 9 / 16 : imageWidth * 1.5;

    // Mine: its number of likes (« J'aime » of other members); another member's: the heart.
    final likes = mine ? item.likesCount : 0;
    final row = VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel:
          '${item.label}, ${mine ? 'ma note' : 'note'} : ${formatScore(item.value)} sur 10'
          '${item.comment == null ? '' : ', ${item.comment}'}'
          '${likes > 0 ? ', ${likesLabel(likes)}' : ''}',
      onPressed: () => mine
          ? context.push(ReviewScreen.location(item.target), extra: RatingSubject.of(item))
          : context.push(titlePath(item.mediaType, item.id)),
      child: Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(VxRadius.poster),
              child: SizedBox(
                width: imageWidth,
                height: imageHeight,
                child: NetImage(url: episode ? (item.stillUrl ?? item.backdropUrl) : item.posterUrl, seed: item.id),
              ),
            ),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.size(16, tv: 24), weight: FontWeight.w600, height: 1.3),
                  ),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(caption, color: VxColors.textSecondary),
                  ),
                  SizedBox(height: layout.space(VxSpace.xxs)),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: layout.space(VxSpace.xs),
                    children: [
                      StarRow(value: item.value, size: caption * 1.2),
                      Text(
                        '${formatScore(item.value)}/10',
                        style: VxText.body(caption, color: VxColors.accent, weight: FontWeight.w600),
                      ),
                      if (likes > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.favorite_rounded, size: caption * 1.1, color: VxColors.textSecondary),
                            SizedBox(width: layout.space(VxSpace.xxs)),
                            Text('$likes', style: VxText.body(caption, color: VxColors.textSecondary)),
                          ],
                        ),
                    ],
                  ),
                  if (item.comment != null) ...[
                    SizedBox(height: layout.space(VxSpace.xxs)),
                    Text(
                      '« ${item.comment} »',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.bodySize, color: VxColors.textSoft),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: layout.space(VxSpace.xs)),
            Icon(Icons.chevron_right_rounded, size: layout.size(22, tv: 34), color: VxColors.textMuted),
          ],
        ),
      ),
    );
    if (mine || item.reviewId == null) return row;
    // Beside the row (its own focus: Right from the row with a remote).
    return Row(
      children: [
        Expanded(child: row),
        SizedBox(width: layout.space(VxSpace.xs)),
        ReviewLikeButton(review: item),
      ],
    );
  }
}
