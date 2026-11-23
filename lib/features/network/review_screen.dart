import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import '../social/review_likes.dart';
import '../tmdb/rating_dialog.dart' show StarRow;
import '../tmdb/review_screen.dart' show ReviewScreen;
import '../tmdb/tmdb.dart';
import 'actions.dart';
import 'comments.dart';
import 'network.dart';
import 'share_image.dart';
import 'widgets.dart';

/// A review and its comments (`/avis/:id`, vixeo_backend/docs/social.md): the title, the author,
/// the stars and the whole comment (behind « Afficher » with spoilers), « J'aime », then the
/// conversation. Mine: « Modifier mon avis » (« Mon avis », `/avis/movie/550`).
class ReviewThreadScreen extends ConsumerStatefulWidget {
  const ReviewThreadScreen({super.key, required this.id});

  final int id;

  static String location(int id) => reviewLocation(id);

  @override
  ConsumerState<ReviewThreadScreen> createState() => _ReviewThreadScreenState();
}

class _ReviewThreadScreenState extends ConsumerState<ReviewThreadScreen> {
  /// Comments added (+) or deleted (−) here, over the number read with the review.
  int _comments = 0;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final review = ref.watch(socialReviewProvider(widget.id));
    final value = review.value;
    if (value == null) {
      return NetworkPage(
        title: 'Avis',
        children: [
          NetworkLoading(
            error: review.error,
            onRetry: () => ref.invalidate(socialReviewProvider(widget.id)),
          ),
        ],
      );
    }
    final item = value.item;
    final comment = item.comment?.trim() ?? '';
    final count = value.commentsCount + _comments;
    return NetworkPage(
      title: value.isMine ? 'Mon avis' : 'Avis de ${value.author.name}',
      actions: [
        VxIconAction(
          icon: Icons.more_horiz_rounded,
          label: 'Options de l’avis',
          dense: true,
          onPressed: () => showReviewMenu(context, ref, value),
        ),
      ],
      onRefresh: () async {
        ref.invalidate(socialReviewProvider(widget.id));
        ref.invalidate(commentsProvider((list: false, id: widget.id)));
        setState(() => _comments = 0);
      },
      children: [
        TitleBanner(title: value.title, subtitle: item.subtitle),
        SizedBox(height: layout.sectionGap),
        VxCard(
          padding: EdgeInsets.all(layout.space(VxSpace.m)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberLine(profile: value.author, at: item.ratedAt),
              SizedBox(height: layout.space(VxSpace.s)),
              Row(
                children: [
                  StarRow(value: item.value, size: layout.size(20, tv: 32)),
                  SizedBox(width: layout.space(VxSpace.xs)),
                  Text(
                    '${formatScore(item.value)}/10',
                    style: VxText.body(layout.bodySize, weight: FontWeight.w700, color: VxColors.accent),
                  ),
                ],
              ),
              if (comment.isNotEmpty) ...[
                SizedBox(height: layout.space(VxSpace.s)),
                SpoilerText(
                  text: comment,
                  spoilers: value.spoilers && !value.isMine,
                  style: VxText.body(layout.bodySize, color: VxColors.text, height: 1.45),
                ),
              ],
              SizedBox(height: layout.space(VxSpace.xs)),
              Row(
                children: [
                  if (!value.isMine && item.reviewId != null) ReviewLikeButton(review: item),
                  if (value.isMine)
                    CountAction(
                      icon: Icons.favorite_border_rounded,
                      count: item.likesCount,
                      label: '${item.likesCount} J’aime',
                    ),
                  CountAction(
                    icon: Icons.mode_comment_outlined,
                    count: count,
                    label: '$count ${count > 1 ? 'commentaires' : 'commentaire'}',
                  ),
                  const Spacer(),
                  if (!DeviceInfo.isTv)
                    CountAction(
                      icon: Icons.ios_share_rounded,
                      count: 0,
                      label: 'Partager en image',
                      onPressed: () => openStory(context, StoryContent.review(value)),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (value.isMine) ...[
          SizedBox(height: layout.space(VxSpace.m)),
          Align(
            alignment: Alignment.centerLeft,
            child: VxButton(
              label: 'Modifier mon avis',
              icon: Icons.edit_outlined,
              kind: VxButtonKind.outline,
              dense: true,
              onPressed: () => context.push(ReviewScreen.location(item.target)),
            ),
          ),
        ],
        SizedBox(height: layout.sectionGap),
        CommentsSection(
          subject: (list: false, id: widget.id),
          onCountChanged: (delta) => setState(() => _comments += delta),
        ),
      ],
    );
  }
}

/// Every review of a title (`/titre/:type/:id/avis`): the most liked first, or the most recent.
class TitleReviewsScreen extends ConsumerStatefulWidget {
  const TitleReviewsScreen({super.key, required this.type, required this.id, this.title});

  final MediaType type;
  final int id;
  final String? title;

  static String location(MediaType type, int id, {String? title}) => Uri(
    path: '/titre/${type.name}/$id/avis',
    queryParameters: {'titre': ?title},
  ).toString();

  @override
  ConsumerState<TitleReviewsScreen> createState() => _TitleReviewsScreenState();
}

class _TitleReviewsScreenState extends ConsumerState<TitleReviewsScreen> {
  final _scroll = ScrollController();
  final _reviews = <SocialReview>[];
  bool _popular = true;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _reviews.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    }
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(networkRepositoryProvider)
          .titleReviews((type: widget.type, id: widget.id), popular: _popular, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _reviews.addAll(page.reviews);
        _page++;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sort(bool popular) {
    if (popular == _popular) return;
    setState(() => _popular = popular);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return NetworkPage(
      title: widget.title == null ? 'Avis' : 'Avis sur ${widget.title}',
      controller: _scroll,
      onRefresh: () => _load(reset: true),
      children: [
        Wrap(
          spacing: layout.space(VxSpace.xs),
          children: [
            VxButton(
              label: 'Populaires',
              kind: _popular ? VxButtonKind.primary : VxButtonKind.outline,
              dense: true,
              autofocus: true,
              onPressed: () => _sort(true),
            ),
            VxButton(
              label: 'Récents',
              kind: _popular ? VxButtonKind.outline : VxButtonKind.primary,
              dense: true,
              onPressed: () => _sort(false),
            ),
          ],
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        if (_reviews.isEmpty && !_loading)
          _error != null
              ? ErrorPanel(error: _error!, onRetry: () => _load(reset: true))
              : const EmptyState(
                  icon: Icons.rate_review_outlined,
                  title: 'Aucun avis',
                  message: 'Personne n’a encore écrit d’avis sur ce titre.',
                ),
        for (final (i, review) in _reviews.indexed) ...[
          if (i > 0) SizedBox(height: layout.listGap),
          ReviewPost(review: review, showTitle: false),
        ],
        if (_loading) const NetworkLoading(),
      ],
    );
  }
}
