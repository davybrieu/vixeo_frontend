import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/models.dart';
import '../profiles/avatars.dart';
import '../social/profile_view.dart' show AccountTile, ProfileHeader;
import '../tmdb/tmdb.dart' show formatScore;
import 'network.dart';
import 'review_screen.dart' show TitleReviewsScreen;
import 'widgets.dart';

/// The social part of a title page (vixeo_backend/docs/social.md): the followed members who watched
/// it and their average, the most liked reviews (« Voir tout »), and lists that have it. Nothing for
/// a guest, a child's profile, or a title nobody talked about.
class TitleSocialSection extends ConsumerWidget {
  const TitleSocialSection({super.key, required this.type, required this.id, required this.name});

  final MediaType type;
  final int id;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final social = ref.watch(titleSocialProvider((type: type, id: id))).value;
    if (social == null || social.isEmpty) return const SizedBox.shrink();
    final gap = SizedBox(height: layout.sectionGap);
    final column = layout.size(720, tv: 1300);
    Widget inColumn(Widget child) => Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: column), child: child),
      ),
    );
    return Padding(
      // A section gap above, like the other sections of the page (none when there is nothing).
      padding: EdgeInsets.only(top: layout.sectionGap),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (social.friends.isNotEmpty) ...[
          const SectionHeader('Vos abonnés'),
          inColumn(_Friends(social: social)),
        ],
        if (social.reviews.isNotEmpty) ...[
          if (social.friends.isNotEmpty) gap,
          SectionHeader(
            'Avis populaires',
            onSeeAll: social.reviewsCount > social.reviews.length
                ? () => context.push(TitleReviewsScreen.location(type, id, title: name))
                : null,
          ),
          inColumn(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, review) in social.reviews.indexed) ...[
                  if (i > 0) SizedBox(height: layout.listGap),
                  ReviewPost(review: review, showTitle: false),
                ],
              ],
            ),
          ),
        ],
        if (social.lists.isNotEmpty) ...[
          if (social.friends.isNotEmpty || social.reviews.isNotEmpty) gap,
          const SectionHeader('Dans les listes'),
          inColumn(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, list) in social.lists.indexed) ...[
                  if (i > 0) SizedBox(height: layout.listGap),
                  ListPost(list: list),
                ],
              ],
            ),
          ),
        ],
      ],
      ),
    );
  }
}

/// « 4 abonnés l'ont vu · moyenne 7,8 », then their avatars with their rating (a press opens their
/// review, or their page).
class _Friends extends StatelessWidget {
  const _Friends({required this.social});

  final TitleSocial social;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(52, tv: 84);
    final count = social.friendsCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$count ${count > 1 ? 'abonnés l’ont vu' : 'abonné l’a vu'}',
                style: VxText.body(layout.bodySize, weight: FontWeight.w700),
              ),
              if (social.friendsAverage case final average?)
                TextSpan(
                  text: ' · moyenne ${formatScore(average)}/10',
                  style: VxText.body(layout.bodySize, color: VxColors.accent, weight: FontWeight.w700),
                ),
            ],
          ),
        ),
        SizedBox(height: layout.space(VxSpace.s)),
        SizedBox(
          height: avatar + layout.size(44, tv: 70),
          child: FocusTraversalGroup(
            policy: vxTraversalPolicy,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: social.friends.length,
              separatorBuilder: (_, _) => SizedBox(width: layout.space(VxSpace.s)),
              itemBuilder: (context, i) {
                final friend = social.friends[i];
                final profile = friend.profile;
                final name = profile.name.trim().isEmpty ? '@${profile.username}' : profile.name;
                final rating = friend.rating;
                return VxFocusable(
                  borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
                  semanticLabel: rating == null ? '$name l’a vu' : '$name : ${formatScore(rating)} sur 10',
                  onPressed: () => context.push(
                    friend.reviewId != null
                        ? reviewLocation(friend.reviewId!)
                        : AccountTile.location(profile.username),
                  ),
                  child: SizedBox(
                    width: avatar + layout.size(16, tv: 24),
                    child: Column(
                      children: [
                        AvatarTile(
                          avatarId: profile.avatar,
                          initial: ProfileHeader.initialOf(profile.name),
                          size: avatar,
                          radius: avatar / 2,
                        ),
                        SizedBox(height: layout.space(VxSpace.xxs)),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(layout.captionSize, weight: FontWeight.w600),
                        ),
                        Text(
                          rating == null ? 'Vu' : '★ ${formatScore(rating)}',
                          style: VxText.body(
                            layout.captionSize,
                            color: rating == null ? VxColors.textSecondary : VxColors.accent,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
