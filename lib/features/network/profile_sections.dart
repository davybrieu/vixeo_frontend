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
import '../catalog/widgets.dart' show titlePath;
import '../social/profile_view.dart';
import '../tmdb/rating_form.dart' show StarRow;
import '../tmdb/tmdb.dart' show formatScore;
import 'actions.dart' show newListLocation;
import 'network.dart';
import 'widgets.dart';

// The parts of a profile page that belong to the social network (vixeo_backend/docs/social.md):
// « Mes 4 favoris » under the header, the « Listes » and « Journal » tabs.

/// Where a profile's lists, diary and year open: mine under `/profil`, a member's under
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
/// of its page, like Letterboxd. Mine, when empty: an invitation to choose them.
class PinnedTitles extends StatelessWidget {
  const PinnedTitles({super.key, required this.titles, this.mine = false});

  final List<MediaItem> titles;
  final bool mine;

  /// « Modifier mon profil » holds the 4 favorites.
  static const editLocation = '/profil/social/edition';

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    if (titles.isEmpty && !mine) return const SizedBox.shrink();
    final label = mine ? 'Mes 4 favoris' : 'Ses 4 favoris';
    if (titles.isEmpty) {
      return VxFocusable(
        borderRadius: layout.size(VxRadius.card, tv: VxRadius.cardTv),
        semanticLabel: 'Choisir mes 4 films ou séries préférés',
        onPressed: () => context.push(editLocation),
        child: Container(
          padding: EdgeInsets.all(layout.space(VxSpace.m)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(layout.size(VxRadius.card, tv: VxRadius.cardTv)),
            border: Border.all(color: VxColors.line),
          ),
          child: Row(
            children: [
              Icon(Icons.push_pin_outlined, color: VxColors.accent, size: layout.size(24, tv: 38)),
              SizedBox(width: layout.space(VxSpace.s)),
              Expanded(
                child: Text(
                  'Choisissez vos 4 films ou séries préférés : ils s’afficheront en haut de votre page.',
                  style: VxText.body(layout.bodySize, color: VxColors.textSoft),
                ),
              ),
            ],
          ),
        ),
      );
    }
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

/// The « Listes » tab: a profile's lists and top 10, the latest first. Mine: « Nouveau top 10 » and
/// « Nouvelle liste ».
class ProfileListsSection extends ConsumerWidget {
  const ProfileListsSection({super.key, required this.username, this.mine = false});

  final String username;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final lists = mine ? ref.watch(myListsProvider(null)) : ref.watch(memberListsProvider(username));
    final buttons = mine
        ? Wrap(
            spacing: layout.space(VxSpace.xs),
            runSpacing: layout.space(VxSpace.xs),
            children: [
              VxButton(
                label: 'Nouveau top 10',
                icon: Icons.format_list_numbered_rounded,
                kind: VxButtonKind.secondary,
                dense: true,
                onPressed: () => context.push(newListLocation(kind: ListKind.top)),
              ),
              VxButton(
                label: 'Nouvelle liste',
                icon: Icons.playlist_add_rounded,
                kind: VxButtonKind.outline,
                dense: true,
                onPressed: () => context.push(newListLocation()),
              ),
            ],
          )
        : null;
    final title = mine ? 'Mes listes' : 'Ses listes';
    final value = lists.value;
    if (value == null) {
      return lists.hasError
          ? ProfileSectionMessage(title: title, message: 'Impossible de charger les listes.')
          : ProfileSectionLoading(title: title, height: layout.size(120, tv: 200));
    }
    if (value.isEmpty) {
      return ProfileSectionMessage(
        title: title,
        message: mine
            ? 'Faites votre top 10 de l’année, vos films cultes, vos séries à voir… Vos listes apparaîtront ici.'
            : 'Aucune liste pour l’instant.',
        action: buttons,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          onSeeAll: value.length > 5 ? () => context.push(profileSectionLocation(mine ? null : username, 'listes')) : null,
        ),
        ProfileColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?buttons,
              if (buttons != null) SizedBox(height: layout.space(VxSpace.m)),
              for (final (i, list) in value.take(5).indexed) ...[
                if (i > 0) SizedBox(height: layout.listGap),
                ListPost(list: list, showAuthor: false),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The « Journal » tab: what a profile watched, the latest first (10), « Bilan de l'année ».
class ProfileDiarySection extends ConsumerWidget {
  const ProfileDiarySection({super.key, required this.username, this.mine = false});

  final String username;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final diary = ref.watch(diaryProvider(username));
    final title = mine ? 'Mon journal' : 'Son journal';
    final member = mine ? null : username;
    final year = DateTime.now().year;
    final review = Align(
      alignment: Alignment.centerLeft,
      child: VxButton(
        label: mine ? 'Mon année $year' : 'Son année $year',
        icon: Icons.insights_rounded,
        kind: VxButtonKind.secondary,
        dense: true,
        onPressed: () => context.push(profileSectionLocation(member, 'bilan')),
      ),
    );
    final value = diary.value;
    if (value == null) {
      return diary.hasError
          ? ProfileSectionMessage(title: title, message: 'Impossible de charger le journal.')
          : ProfileSectionLoading(title: title, height: layout.size(160, tv: 260));
    }
    if (value.isEmpty) {
      return ProfileSectionMessage(
        title: title,
        message: mine
            ? 'Chaque film ou épisode marqué comme vu s’inscrit ici, avec sa date et votre note.'
            : 'Rien dans son journal pour l’instant.',
        action: review,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title, onSeeAll: () => context.push(profileSectionLocation(member, 'journal'))),
        ProfileColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              review,
              SizedBox(height: layout.space(VxSpace.m)),
              for (final entry in value.take(10)) DiaryRow(entry: entry),
            ],
          ),
        ),
      ],
    );
  }
}

/// A line of the diary: the day, the poster, the title (or the episode), the rating, « Revu ».
class DiaryRow extends StatelessWidget {
  const DiaryRow({super.key, required this.entry, this.onLongPress});

  final DiaryEntry entry;

  /// Mine: « Retirer du journal ».
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final at = entry.watchedAt;
    final title = entry.title;
    final detail =
        entry.episodeLabel ??
        [title.type == MediaType.movie ? 'Film' : 'Série', if (title.year != null) '${title.year}'].join(' · ');
    final rating = entry.rating;
    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: [
        '${at.day} ${frenchMonths[at.month - 1]}',
        title.title,
        detail,
        if (entry.rewatch) 'revu',
        if (rating != null) 'noté ${formatScore(rating)} sur 10',
      ].join(', '),
      onPressed: () => context.push(titlePath(title.type, title.id)),
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.xxs), horizontal: layout.space(VxSpace.xxs)),
        child: Row(
          children: [
            SizedBox(
              width: layout.size(40, tv: 64),
              child: Column(
                children: [
                  Text('${at.day}', style: VxText.title(layout.size(20, tv: 32))),
                  Text(
                    frenchMonths[at.month - 1].substring(0, 3),
                    style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(width: layout.space(VxSpace.s)),
            PosterThumb(url: title.posterUrl, width: layout.size(40, tv: 64), seed: title.id),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                  ),
                  if (rating != null) ...[
                    SizedBox(height: layout.space(VxSpace.xxs)),
                    StarRow(value: rating, size: layout.size(13, tv: 20)),
                  ],
                ],
              ),
            ),
            if (entry.rewatch)
              Icon(
                Icons.replay_rounded,
                size: layout.size(18, tv: 28),
                color: VxColors.textSecondary,
                semanticLabel: 'Revu',
              ),
          ],
        ),
      ),
    );
  }
}
