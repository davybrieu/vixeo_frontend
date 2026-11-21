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
import '../catalog/widgets.dart' show titlePath;
import '../search/filter_bar.dart';
import '../search/search_filters.dart' show Decade;
import '../social/social_repository.dart' show socialReviewsProvider;
import 'rating_dialog.dart';
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
  Decade? _decade;

  /// The review's rating, at least.
  int? _minRating;
  ReviewSort _sort = ReviewSort.recent;

  bool get _filtered => _type != null || _decade != null || _minRating != null || _sort != ReviewSort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickDecade() async {
    final choice = await showVxChoice<Decade>(
      context,
      title: 'Années',
      selected: _decade,
      options: [(null, 'Toutes les années'), for (final d in Decade.values) (d, d.label)],
    );
    if (choice != null) setState(() => _decade = choice.$1);
  }

  Future<void> _pickRating() async {
    final choice = await showVxChoice<int>(
      context,
      title: 'Note de l’avis',
      selected: _minRating,
      options: [(null, 'Toutes les notes'), for (final r in const [5, 6, 7, 8, 9]) (r, '$r et plus')],
    );
    if (choice != null) setState(() => _minRating = choice.$1);
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
      decade: _decade,
      minRating: _minRating,
      sort: _sort,
    );

    Widget body;
    if (member != null) {
      body = _ReviewsList(
        reviews: ref.watch(socialReviewsProvider(member)),
        filters: filters,
        mine: false,
        onRefresh: () async {
          ref.invalidate(socialReviewsProvider(member));
          await ref.read(socialReviewsProvider(member).future);
        },
      );
    } else {
      body = _ReviewsList(
        reviews: ref.watch(reviewsProvider),
        filters: filters,
        mine: true,
        onRefresh: () async {
          ref.invalidate(reviewsProvider);
          await ref.read(reviewsProvider.future);
        },
      );
    }

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
                    label: _decade?.label ?? 'Années',
                    semanticLabel: 'Années : ${_decade?.label ?? 'toutes'}',
                    selected: _decade != null,
                    dropdown: true,
                    onPressed: _pickDecade,
                  ),
                  SizedBox(width: gap),
                  FilterChipButton(
                    label: _minRating == null ? 'Note' : 'Note $_minRating+',
                    semanticLabel: 'Note de l’avis : ${_minRating == null ? 'toutes' : '$_minRating et plus'}',
                    selected: _minRating != null,
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
                        _decade = null;
                        _minRating = null;
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
    required this.decade,
    required this.minRating,
    required this.sort,
  });

  final RatedType? type;
  final String query;
  final Decade? decade;
  final int? minRating;
  final ReviewSort sort;

  bool matches(RatedItem item) {
    if (type != null && item.type != type) return false;
    if (!item.matches(query)) return false;
    final year = item.year;
    if (decade != null && (year == null || !decade!.contains(year))) return false;
    if (minRating != null && item.value < minRating!) return false;
    return true;
  }

  /// [items] (the most recently rated first, as the API and `reviewsProvider` keep them) in this
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
  const _ReviewsList({required this.reviews, required this.filters, required this.mine, required this.onRefresh});

  final AsyncValue<List<RatedItem>> reviews;
  final _ReviewFilters filters;
  final bool mine;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);

    return AsyncView(
      value: reviews,
      onRetry: onRefresh,
      data: (all) {
        final items = filters.sorted([
          for (final item in all)
            if (filters.matches(item)) item,
        ]);
        if (items.isEmpty) {
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
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(height: layout.space(VxSpace.s)),
                itemBuilder: (_, i) => ReviewRow(item: items[i], mine: mine),
              ),
            ),
          ),
        );
      },
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

    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel:
          '${item.label}, ${mine ? 'ma note' : 'note'} : ${formatScore(item.value)} sur 10'
          '${item.comment == null ? '' : ', ${item.comment}'}',
      onPressed: () => context.push(mine ? ReviewScreen.location(item.target) : titlePath(item.mediaType, item.id)),
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
  }
}
