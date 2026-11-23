import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart' show titlePath;
import '../library/library.dart';
import '../notifications/inbox.dart' show dayLabel, hourMinute;
import '../social/profile_view.dart';
import '../social/social_repository.dart';
import '../tmdb/rating_form.dart' show StarRow;
import '../tmdb/tmdb.dart' show formatScore;
import 'actions.dart' show newListLocation;
import 'network.dart';
import 'widgets.dart';

// The parts of a profile page that belong to the social network (vixeo_backend/docs/social.md):
// « Mes 4 favoris » under the header, the « Activité » and « Listes » tabs.

/// Where a profile's lists and year open: mine under `/profil`, a member's under
/// `/membre/:username`.
String profileSectionLocation(String? username, String section, {Map<String, String>? query}) => Uri(
  path: username == null ? '/profil/$section' : '/membre/${Uri.encodeComponent(username)}/$section',
  queryParameters: query,
).toString();

/// French months, January first.
const frenchMonths = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];

/// « Mes 4 favoris » (`pinned_titles`): the 4 movies or TV shows a profile chose to show at the top
/// of its page, like Letterboxd; chosen in « Modifier le profil ». Nothing when there are none (no
/// invitation: developer's request, 23/11/2026).
class PinnedTitles extends StatelessWidget {
  const PinnedTitles({super.key, required this.titles, this.mine = false});

  final List<MediaItem> titles;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    if (titles.isEmpty) return const SizedBox.shrink();
    final label = mine ? 'Mes 4 favoris' : 'Ses 4 favoris';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: VxText.body(layout.captionSize, weight: FontWeight.w700, color: VxColors.textSecondary)),
        SizedBox(height: layout.space(VxSpace.xs)),
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = layout.cardGap;
            final width = ((constraints.maxWidth - gap * 3) / 4).clamp(0.0, layout.size(140, tv: 220));
            return FocusTraversalGroup(
              policy: vxTraversalPolicy,
              child: Row(
                children: [
                  for (final (i, title) in titles.take(4).indexed) ...[
                    if (i > 0) SizedBox(width: gap),
                    VxFocusable(
                      borderRadius: width * 0.08,
                      semanticLabel: '$label : ${title.title}',
                      onPressed: () => context.push(titlePath(title.type, title.id)),
                      child: PosterThumb(url: title.posterUrl, width: width, seed: title.id),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// « À voir » among the lists (developer's request, 23/11/2026: « Ma liste » merged into the
/// lists): the movies and series to watch later (the synced `favorite` group), always first, never
/// deleted, without a title or a description to choose. A press opens it ([location], a member's
/// [memberLocation]).
class WatchlistCard extends ConsumerWidget {
  const WatchlistCard({super.key, this.username});

  /// A member's; null: mine.
  final String? username;

  static const name = 'À voir';

  static const location = '/listes/a-voir';

  static String memberLocation(String username) => '/membre/${Uri.encodeComponent(username)}/a-voir';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final member = username;
    final List<MediaItem>? titles;
    final int? count;
    if (member == null) {
      titles = ref.watch(libraryProvider).value?.toWatch;
      count = titles?.length;
    } else {
      titles = ref.watch(socialTitlesProvider(member)).value;
      count = ref.watch(socialProfileProvider(member)).value?.listCount ?? titles?.length;
    }
    final covers = [
      for (final title in titles ?? const <MediaItem>[])
        if (title.posterUrl case final url?) url,
    ].take(4).toList();
    final summary = count == null ? '' : titleCount(count);
    return VxCard(
      padding: EdgeInsets.all(layout.space(VxSpace.m)),
      child: VxFocusable(
        borderRadius: layout.size(VxRadius.card, tv: VxRadius.cardTv),
        semanticLabel: '${WatchlistCard.name}, $summary',
        onPressed: () => context.push(member == null ? location : memberLocation(member)),
        child: Row(
          children: [
            PosterMosaic(urls: covers, height: layout.size(96, tv: 150)),
            SizedBox(width: layout.space(VxSpace.m)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bookmark_rounded, size: layout.size(18, tv: 28), color: VxColors.accent),
                      SizedBox(width: layout.space(VxSpace.xxs)),
                      Flexible(
                        child: Text(
                          WatchlistCard.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (summary.isNotEmpty)
                    Text(summary, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
                  SizedBox(height: layout.space(VxSpace.xxs)),
                  Text(
                    member == null ? 'Les films et séries à regarder plus tard.' : 'Ses films et séries à regarder.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.captionSize, color: VxColors.textSoft),
                  ),
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

/// The « Listes » tab: « À voir » first (always there, never deleted), then the profile's lists,
/// the latest first. Mine: « Nouvelle liste ».
class ProfileListsSection extends ConsumerWidget {
  const ProfileListsSection({super.key, required this.username, this.mine = false});

  final String username;
  final bool mine;

  /// Lists shown in the tab before « Voir tout ».
  static const shown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final lists = mine ? ref.watch(myListsProvider(null)) : ref.watch(memberListsProvider(username));
    final title = mine ? 'Mes listes' : 'Ses listes';
    final value = lists.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          onSeeAll: (value?.length ?? 0) > shown
              ? () => context.push(profileSectionLocation(mine ? null : username, 'listes'))
              : null,
        ),
        ProfileColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mine) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: VxButton(
                    label: 'Nouvelle liste',
                    icon: Icons.playlist_add_rounded,
                    kind: VxButtonKind.secondary,
                    dense: true,
                    onPressed: () => context.push(newListLocation()),
                  ),
                ),
                SizedBox(height: layout.space(VxSpace.m)),
              ],
              WatchlistCard(username: mine ? null : username),
              if (value == null)
                Padding(
                  padding: EdgeInsets.only(top: layout.listGap),
                  child: lists.hasError
                      ? Text(
                          'Impossible de charger les listes.',
                          style: VxText.body(layout.bodySize, color: VxColors.textSecondary),
                        )
                      : SizedBox(
                          height: layout.size(120, tv: 200),
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                )
              else if (value.isEmpty && mine)
                Padding(
                  padding: EdgeInsets.only(top: layout.listGap),
                  child: Text(
                    'Créez vos listes, par exemple « Top 10 de ${DateTime.now().year} », et rangez les titres dans '
                    'l’ordre de votre choix.',
                    style: VxText.body(layout.bodySize, color: VxColors.textSecondary),
                  ),
                )
              else
                for (final list in value.take(shown)) ...[
                  SizedBox(height: layout.listGap),
                  ListPost(list: list, showAuthor: false),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

/// « Aujourd’hui », « Hier », « Lundi 17 novembre » (with the year when it isn't this one).
String activityDay(DateTime at, DateTime now) {
  final day = dayLabel(at, now);
  return '${day[0].toUpperCase()}${day.substring(1)}';
}

/// The « Activité » tab (developer's request, 23/11/2026: « la liste de tes actions avec la
/// date »): what a profile did, the most recent first, under the day it was done: reviews, lists,
/// titles watched and liked, each with its time. « Afficher plus » reads the next page.
class ProfileActivitySection extends ConsumerWidget {
  const ProfileActivitySection({super.key, required this.username, this.mine = false});

  final String username;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final title = mine ? 'Mon activité' : 'Son activité';
    final activity = ref.watch(activityProvider(username));
    final page = activity.value;
    if (page == null) {
      return activity.hasError
          ? ProfileSectionMessage(title: title, message: 'Impossible de charger l’activité.')
          : ProfileSectionLoading(title: title, height: layout.size(160, tv: 260));
    }
    if (page.items.isEmpty) {
      return ProfileSectionMessage(
        title: title,
        message: mine
            ? 'Vos avis, vos listes, les titres que vous voyez et ceux que vous aimez apparaîtront ici, avec leur date.'
            : 'Aucune activité pour l’instant.',
      );
    }
    final now = DateTime.now();
    String? day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        ProfileColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in page.items) ...[
                if (item.createdAt case final at? when activityDay(at, now) != day) ...[
                  if (day != null) SizedBox(height: layout.space(VxSpace.m)),
                  Padding(
                    padding: EdgeInsets.only(bottom: layout.space(VxSpace.xs)),
                    child: Text(
                      day = activityDay(at, now),
                      style: VxText.body(layout.captionSize, weight: FontWeight.w700, color: VxColors.textSecondary),
                    ),
                  ),
                ],
                ActivityRow(item: item),
              ],
              if (page.next != null) ...[
                SizedBox(height: layout.space(VxSpace.s)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: VxButton(
                    label: 'Afficher plus',
                    icon: Icons.expand_more_rounded,
                    kind: VxButtonKind.secondary,
                    dense: true,
                    onPressed: () => ref.read(activityProvider(username).notifier).loadMore(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// An action of the « Activité » tab: what was done (« Vu », « Aimé », « Noté 8/10 », « Liste
/// créée »), on what, at what time. A press opens the title, the review or the list.
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final at = item.createdAt;
    final time = at == null ? null : hourMinute(at);
    final (IconData icon, String action, String subject, String location, Widget image) = switch (item) {
      FeedReview(:final review) => (
        Icons.star_rounded,
        'Noté ${formatScore(review.item.value)}/10',
        review.item.episodeNumber == null
            ? review.item.title
            : '${review.item.title} · S${review.item.seasonNumber} É${review.item.episodeNumber}',
        reviewLocation(review.id),
        PosterThumb(url: review.item.posterUrl, width: layout.size(40, tv: 64), seed: review.item.id),
      ),
      FeedList(:final list) => (
        Icons.playlist_add_check_rounded,
        'Liste · ${list.summary}',
        list.title,
        listLocation(list.id),
        PosterThumb(url: list.cover.firstOrNull, width: layout.size(40, tv: 64), seed: list.id),
      ),
      FeedWatched(:final title, :final episodesCount, :final rewatch) => (
        Icons.visibility_rounded,
        episodesCount > 1 ? 'Vu · $episodesCount épisodes' : (rewatch ? 'Revu' : 'Vu'),
        title.title,
        titlePath(title.type, title.id),
        PosterThumb(url: title.posterUrl, width: layout.size(40, tv: 64), seed: title.id),
      ),
      FeedLiked(:final title) => (
        Icons.favorite_rounded,
        'Aimé',
        title.title,
        titlePath(title.type, title.id),
        PosterThumb(url: title.posterUrl, width: layout.size(40, tv: 64), seed: title.id),
      ),
    };
    final comment = switch (item) {
      FeedReview(:final review) when !review.spoilers => review.item.comment?.trim() ?? '',
      _ => '',
    };
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: [action, subject, ?time].join(', '),
      onPressed: () => context.push(location),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.xxs), horizontal: layout.space(VxSpace.xxs)),
        child: Row(
          children: [
            image,
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: layout.size(15, tv: 24), color: VxColors.accent),
                      SizedBox(width: layout.space(VxSpace.xxs)),
                      Flexible(
                        child: Text(
                          action,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                  ),
                  if (item case FeedReview(:final review)) ...[
                    SizedBox(height: layout.space(VxSpace.xxs)),
                    StarRow(value: review.item.value, size: layout.size(13, tv: 20)),
                  ],
                  if (comment.isNotEmpty)
                    Text(
                      comment,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.captionSize, color: VxColors.textSoft),
                    ),
                ],
              ),
            ),
            if (time != null) ...[
              SizedBox(width: layout.space(VxSpace.s)),
              Text(time, style: VxText.body(layout.captionSize, color: VxColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
