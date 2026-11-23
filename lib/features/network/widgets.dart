import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart' show titlePath;
import '../notifications/inbox.dart' show timeAgo;
import '../profiles/avatars.dart';
import '../social/profile_view.dart' show AccountTile, ProfileHeader;
import '../social/review_likes.dart';
import '../social/social_repository.dart';
import '../tmdb/rating_form.dart' show StarRow;
import '../tmdb/tmdb.dart';
import 'actions.dart';
import 'network.dart';

// The cards of the social network (vixeo_backend/docs/social.md): a review, a list, a title
// watched. The same in the feed, on a title page, on a member's page; a press opens the review,
// the list or the title. Every interactive part goes through VxFocusable (remote).

/// Where a review opens: its page, with its comments.
String reviewLocation(int id) => '/avis/$id';

/// Where a list opens.
String listLocation(int id) => '/listes/$id';

/// A poster, rounded, at a given width (2:3).
class PosterThumb extends StatelessWidget {
  const PosterThumb({super.key, required this.url, required this.width, this.seed = 0});

  final String? url;
  final double width;
  final int seed;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(width * 0.08),
    child: SizedBox(
      width: width,
      height: width * 1.5,
      child: NetImage(url: url, seed: seed),
    ),
  );
}

/// The covers of a list: its first 4 posters side by side (a dark tile without any).
class PosterMosaic extends StatelessWidget {
  const PosterMosaic({super.key, required this.urls, required this.height, this.seed = 0});

  final List<String> urls;
  final double height;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final width = height / 1.5;
    if (urls.isEmpty) {
      return Container(
        width: width * 2,
        height: height,
        decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(width * 0.08)),
        child: Icon(Icons.playlist_play_rounded, color: VxColors.textMuted, size: height * 0.4),
      );
    }
    // The posters overlap a little, the first one on top.
    final step = width * 0.55;
    return SizedBox(
      width: width + step * (urls.length - 1),
      height: height,
      child: Stack(
        children: [
          for (final (i, url) in urls.indexed.toList().reversed)
            Positioned(
              left: step * i,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(width * 0.08),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
                ),
                child: PosterThumb(url: url, width: width, seed: seed + i),
              ),
            ),
        ],
      ),
    );
  }
}

/// A text that reveals the story: hidden behind « Afficher » until the reader asks.
class SpoilerText extends StatefulWidget {
  const SpoilerText({super.key, required this.text, required this.spoilers, this.maxLines, this.style});

  final String text;
  final bool spoilers;
  final int? maxLines;
  final TextStyle? style;

  @override
  State<SpoilerText> createState() => _SpoilerTextState();
}

class _SpoilerTextState extends State<SpoilerText> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final style = widget.style ?? VxText.body(layout.bodySize, color: VxColors.textSoft);
    if (!widget.spoilers || _shown) {
      return Text(
        widget.text,
        maxLines: widget.maxLines,
        overflow: widget.maxLines == null ? null : TextOverflow.ellipsis,
        style: style,
      );
    }
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: 'Contient des spoilers. Afficher',
      onPressed: () => setState(() => _shown = true),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.s), vertical: layout.space(VxSpace.xs)),
        decoration: BoxDecoration(
          color: VxColors.text.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(layout.size(VxRadius.button, tv: VxRadius.buttonTv)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off_outlined, size: layout.size(18, tv: 28), color: VxColors.textSecondary),
            SizedBox(width: layout.space(VxSpace.xs)),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Contient des spoilers · ', style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                    TextSpan(
                      text: 'Afficher',
                      style: VxText.body(layout.captionSize, color: VxColors.accent, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A member, small: avatar, name, « @pseudo · il y a 5 min ». A press opens their page.
class MemberLine extends StatelessWidget {
  const MemberLine({super.key, required this.profile, this.at, this.trailing});

  final SocialProfile profile;
  final DateTime? at;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(36, tv: 56);
    final name = profile.name.trim().isEmpty ? '@${profile.username}' : profile.name;
    final when = at == null ? null : timeAgo(at!, DateTime.now());
    return Row(
      children: [
        Expanded(
          child: VxFocusable(
            borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
            semanticLabel: '$name, @${profile.username}${when == null ? '' : ', $when'}',
            onPressed: () => context.push(AccountTile.location(profile.username)),
            child: Row(
              children: [
                AvatarTile(
                  avatarId: profile.avatar,
                  initial: ProfileHeader.initialOf(profile.name),
                  size: avatar,
                  radius: avatar / 2,
                ),
                SizedBox(width: layout.space(VxSpace.xs)),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(layout.bodySize, weight: FontWeight.w700, height: 1.2),
                      ),
                      Text(
                        when == null ? '@${profile.username}' : '@${profile.username} · $when',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// An icon and a number (comments…), pressable.
class CountAction extends StatelessWidget {
  const CountAction({super.key, required this.icon, required this.count, required this.label, this.onPressed, this.color});

  final IconData icon;
  final int count;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: label,
      onPressed: onPressed,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: layout.size(40, tv: 60), minWidth: layout.size(40, tv: 60)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.xs)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: layout.size(20, tv: 30), color: color ?? VxColors.textSecondary),
              if (count > 0) ...[
                SizedBox(width: layout.space(VxSpace.xxs)),
                Text('$count', style: VxText.body(layout.captionSize, color: color ?? VxColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The « … » of a card: a menu (report, send to a friend…).
class MoreButton extends StatelessWidget {
  const MoreButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CountAction(icon: Icons.more_horiz_rounded, count: 0, label: label, onPressed: onPressed);
}

/// A review as a publication (feed, title page, member page): author, title, stars, comment
/// (behind « Afficher » with spoilers), likes and comments. A press opens its page.
class ReviewPost extends ConsumerWidget {
  const ReviewPost({super.key, required this.review, this.at, this.showTitle = true});

  final SocialReview review;
  final DateTime? at;

  /// The title reviewed (not on its own page).
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final item = review.item;
    final comment = item.comment?.trim() ?? '';
    final poster = layout.size(56, tv: 90);
    return VxCard(
      padding: EdgeInsets.all(layout.space(VxSpace.m)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberLine(
            profile: review.author,
            at: at ?? item.ratedAt,
            trailing: MoreButton(label: 'Options de l’avis', onPressed: () => showReviewMenu(context, ref, review)),
          ),
          SizedBox(height: layout.space(VxSpace.s)),
          VxFocusable(
            borderRadius: layout.size(VxRadius.card, tv: VxRadius.cardTv),
            semanticLabel:
                '${review.author.name} : ${item.label}, ${formatScore(item.value)} sur 10${comment.isEmpty ? '' : '. Ouvrir l’avis'}',
            onPressed: () => context.push(reviewLocation(review.id)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTitle) ...[
                  PosterThumb(url: item.posterUrl, width: poster, seed: item.id),
                  SizedBox(width: layout.space(VxSpace.s)),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showTitle) ...[
                        Text(
                          item.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                        ),
                        Text(item.subtitle, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                        SizedBox(height: layout.space(VxSpace.xxs)),
                      ],
                      Row(
                        children: [
                          StarRow(value: item.value, size: layout.size(16, tv: 26)),
                          SizedBox(width: layout.space(VxSpace.xs)),
                          Text(
                            '${formatScore(item.value)}/10',
                            style: VxText.body(layout.captionSize, weight: FontWeight.w700, color: VxColors.accent),
                          ),
                        ],
                      ),
                      if (comment.isNotEmpty) ...[
                        SizedBox(height: layout.space(VxSpace.xs)),
                        SpoilerText(text: comment, spoilers: review.spoilers, maxLines: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: layout.space(VxSpace.xs)),
          Row(
            children: [
              if (!review.isMine && item.reviewId != null) ReviewLikeButton(review: item),
              if (review.isMine)
                CountAction(
                  icon: Icons.favorite_border_rounded,
                  count: item.likesCount,
                  label: '${item.likesCount} J’aime',
                ),
              CountAction(
                icon: Icons.mode_comment_outlined,
                count: review.commentsCount,
                label: review.commentsCount == 0
                    ? 'Commenter'
                    : '${review.commentsCount} ${review.commentsCount > 1 ? 'commentaires' : 'commentaire'}',
                onPressed: () => context.push(reviewLocation(review.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A list or a top 10 as a publication: its covers, its title and author, likes and comments. A
/// press opens it.
class ListPost extends ConsumerWidget {
  const ListPost({super.key, required this.list, this.at, this.showAuthor = true});

  final SocialList list;
  final DateTime? at;
  final bool showAuthor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    return VxCard(
      padding: EdgeInsets.all(layout.space(VxSpace.m)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAuthor) ...[
            MemberLine(
              profile: list.author,
              at: at ?? list.updatedAt,
              trailing: MoreButton(label: 'Options de la liste', onPressed: () => showListMenu(context, ref, list)),
            ),
            SizedBox(height: layout.space(VxSpace.s)),
          ],
          VxFocusable(
            borderRadius: layout.size(VxRadius.card, tv: VxRadius.cardTv),
            semanticLabel: '${list.title}, ${list.summary}, de ${list.author.name}',
            onPressed: () => context.push(listLocation(list.id)),
            child: Row(
              children: [
                PosterMosaic(urls: list.cover, height: layout.size(96, tv: 150), seed: list.id),
                SizedBox(width: layout.space(VxSpace.m)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (list.kind == ListKind.top)
                        Padding(
                          padding: EdgeInsets.only(bottom: layout.space(VxSpace.xxs)),
                          child: const VxBadge('TOP 10', accent: true),
                        ),
                      Text(
                        list.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                      ),
                      Text(list.summary, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                      if ((list.description ?? '').trim().isNotEmpty) ...[
                        SizedBox(height: layout.space(VxSpace.xxs)),
                        Text(
                          list.description!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(layout.captionSize, color: VxColors.textSoft),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: layout.space(VxSpace.xs)),
          Row(
            children: [
              ListLikeButton(list: list),
              CountAction(
                icon: Icons.mode_comment_outlined,
                count: list.commentsCount,
                label: list.commentsCount == 0
                    ? 'Commenter'
                    : '${list.commentsCount} ${list.commentsCount > 1 ? 'commentaires' : 'commentaire'}',
                onPressed: () => context.push(listLocation(list.id)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A title watched by followed members (« Léa et Max ont vu… »). A press opens the title.
class WatchedPost extends StatelessWidget {
  const WatchedPost({super.key, required this.item});

  final FeedWatched item;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(28, tv: 44);
    final title = item.title;
    final when = item.createdAt == null ? null : timeAgo(item.createdAt!, DateTime.now());
    return VxCard(
      padding: EdgeInsets.all(layout.space(VxSpace.m)),
      child: VxFocusable(
        borderRadius: layout.size(VxRadius.card, tv: VxRadius.cardTv),
        semanticLabel: '${item.sentence} ${title.title}${when == null ? '' : ', $when'}',
        onPressed: () => context.push(titlePath(title.type, title.id)),
        child: Row(
          children: [
            PosterThumb(url: title.posterUrl, width: layout.size(48, tv: 76), seed: title.id),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final (i, p) in item.profiles.indexed)
                        Transform.translate(
                          offset: Offset(-avatar * 0.3 * i, 0),
                          child: AvatarTile(
                            avatarId: p.avatar,
                            initial: ProfileHeader.initialOf(p.name),
                            size: avatar,
                            radius: avatar / 2,
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: layout.space(VxSpace.xxs)),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${item.sentence} ', style: VxText.body(layout.bodySize, color: VxColors.textSoft)),
                        TextSpan(text: title.title, style: VxText.body(layout.bodySize, weight: FontWeight.w700)),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (when != null)
                    Text(when, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: layout.size(22, tv: 34), color: VxColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// The heart of a list (not one's own): liked at once, put back if the API refuses.
class ListLikeButton extends ConsumerStatefulWidget {
  const ListLikeButton({super.key, required this.list, this.onChanged});

  final SocialList list;
  final ValueChanged<SocialList>? onChanged;

  @override
  ConsumerState<ListLikeButton> createState() => _ListLikeButtonState();
}

class _ListLikeButtonState extends ConsumerState<ListLikeButton> {
  late bool _liked = widget.list.liked;
  late int _count = widget.list.likesCount;
  bool _busy = false;

  @override
  void didUpdateWidget(ListLikeButton old) {
    super.didUpdateWidget(old);
    if (old.list.liked != widget.list.liked || old.list.likesCount != widget.list.likesCount) {
      _liked = widget.list.liked;
      _count = widget.list.likesCount;
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final before = (_liked, _count);
    setState(() {
      _busy = true;
      _liked = !_liked;
      _count += _liked ? 1 : -1;
    });
    try {
      final after = await ref.read(networkRepositoryProvider).likeList(widget.list.id, liked: _liked);
      if (!mounted) return;
      setState(() {
        _liked = after.liked;
        _count = after.likesCount;
      });
      widget.onChanged?.call(widget.list.copyWith(liked: after.liked, likesCount: after.likesCount));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _liked = before.$1;
          _count = before.$2;
        });
      }
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.list.isMine) {
      return CountAction(icon: Icons.favorite_border_rounded, count: _count, label: '$_count J’aime');
    }
    return CountAction(
      icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      count: _count,
      color: _liked ? VxColors.dangerText : null,
      label: _liked ? 'Je n’aime plus cette liste, $_count J’aime' : 'J’aime cette liste, $_count J’aime',
      onPressed: _toggle,
    );
  }
}

/// A row of titles of the social network (numbered for a top 10): their posters, a press opens
/// each one.
class NumberedPosters extends StatelessWidget {
  const NumberedPosters({super.key, required this.titles, this.numbered = false});

  final List<MediaItem> titles;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final width = layout.size(110, tv: 180);
    return Wrap(
      spacing: layout.cardGap,
      runSpacing: layout.space(VxSpace.m),
      children: [
        for (final (i, title) in titles.indexed)
          SizedBox(
            width: width,
            child: VxFocusable(
              borderRadius: layout.size(VxRadius.card, tv: VxRadius.cardTv),
              semanticLabel: '${numbered ? '${i + 1}. ' : ''}${title.title}${title.year == null ? '' : ', ${title.year}'}',
              onPressed: () => context.push(titlePath(title.type, title.id)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      PosterThumb(url: title.posterUrl, width: width, seed: title.id),
                      if (numbered)
                        Positioned(
                          left: layout.space(VxSpace.xxs),
                          top: layout.space(VxSpace.xxs),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.xs), vertical: 2),
                            decoration: BoxDecoration(
                              color: VxColors.accent,
                              borderRadius: BorderRadius.circular(layout.size(8, tv: 12)),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: VxText.title(layout.size(16, tv: 26), color: VxColors.onAccent),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: layout.space(VxSpace.xxs)),
                  Text(
                    title.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.captionSize, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A page of the social network opened over another one: back button, title (with round
/// [actions] on its right), then [children] in a column of reading width. [onRefresh]: pull to
/// refresh; [controller]: to load more at the end.
class NetworkPage extends StatelessWidget {
  const NetworkPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.onRefresh,
    this.controller,
    this.bottom,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final RefreshCallback? onRefresh;
  final ScrollController? controller;

  /// Fixed under the page (a field to write a comment…).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    Widget list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pageContentPadding(context),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.size(720, tv: 1200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
    if (onRefresh != null) list = RefreshIndicator(onRefresh: onRefresh!, child: list);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VxPageHeader(title: title, back: true, actions: actions),
            Expanded(child: list),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

/// A loading page body, or its error with « Réessayer ».
class NetworkLoading extends StatelessWidget {
  const NetworkLoading({super.key, this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => error == null
      ? const Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: CircularProgressIndicator()),
        )
      : ErrorPanel(error: error!, onRetry: onRetry);
}

/// The title of a review or a list page: poster, title, year or episode, « Voir la fiche ».
class TitleBanner extends StatelessWidget {
  const TitleBanner({super.key, required this.title, this.subtitle, this.trailing});

  final MediaItem title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return VxFocusable(
      borderRadius: layout.size(VxRadius.card, tv: VxRadius.cardTv),
      semanticLabel: '${title.title}${subtitle == null ? '' : ', $subtitle'}. Voir la fiche',
      onPressed: () => context.push(titlePath(title.type, title.id)),
      child: Row(
        children: [
          PosterThumb(url: title.posterUrl, width: layout.size(72, tv: 120), seed: title.id),
          SizedBox(width: layout.space(VxSpace.s)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.title(layout.size(20, tv: 34)),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                SizedBox(height: layout.space(VxSpace.xxs)),
                Text(
                  'Voir la fiche',
                  style: VxText.body(layout.captionSize, weight: FontWeight.w700, color: VxColors.accent),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
