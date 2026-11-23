import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'rating_view.dart';

/// The rating of a title page (IMDb's, else TMDb's): a press shows every rating ([showAllRatings]).
/// A small arrow says it opens something. Nothing when neither rates it.
class RatingButton extends StatelessWidget {
  const RatingButton({super.key, required this.ratings, required this.name, this.title, this.fontSize = 14});

  final TitleRatings ratings;

  /// The title's name, written under « Notes ».
  final String name;

  /// The movie or show: « Notes » also asks the other sites' ratings (MDBList) when it opens.
  final ({MediaType type, int id})? title;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final shown = ratings.shown;
    if (shown == null) return const SizedBox.shrink();
    final (site, rating) = shown;
    return VxFocusable(
      borderRadius: fontSize * 0.5,
      semanticLabel: 'Note ${site.label} : ${formatRating(rating.value)} sur 10. Voir les notes',
      onPressed: () => showAllRatings(context, ratings: ratings, name: name, title: title),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RatingLabel(site: site, value: rating.value, fontSize: fontSize),
            SizedBox(width: fontSize * 0.1),
            Icon(Icons.chevron_right_rounded, size: fontSize * 1.3, color: VxColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// « Notes »: IMDb's and TMDb's ratings of a title or an episode ([name]), each with its logo and
/// its number of votes, then, for a movie or a show ([title]), those of the other sites (Trakt,
/// Letterboxd, Rotten Tomatoes, Metacritic, MyAnimeList; MDBList, asked only now, on their own
/// scales). A sheet on a phone (above the tab bar), a window elsewhere (with « Fermer », focused for
/// the remote).
Future<void> showAllRatings(
  BuildContext context, {
  required TitleRatings ratings,
  required String name,
  ({MediaType type, int id})? title,
}) {
  final layout = Layout.of(context);
  final content = _AllRatings(ratings: ratings, name: name, title: title);
  if (layout.isPhone) {
    return showModalBottomSheet<void>(
      // Above the phone's tab bar, drawn over the pages' navigator (AppShell).
      useRootNavigator: true,
      context: context,
      backgroundColor: VxColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8),
        child: content,
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: VxColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: layout.isLarge ? layout.tv(620) : 480,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
        ),
        child: content,
      ),
    ),
  );
}

class _AllRatings extends ConsumerWidget {
  const _AllRatings({required this.ratings, required this.name, required this.title});

  final TitleRatings ratings;
  final String name;
  final ({MediaType type, int id})? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final phone = layout.isPhone;
    final s = layout.isLarge ? layout.tv(1) * 1.6 : 1.0;
    final title = this.title;
    // Watched first here: MDBList is never asked before « Notes » opens (an episode: never).
    final others = title == null ? null : ref.watch(externalRatingsProvider((title.type, title.id)));
    final found = others?.value ?? const <RatingSite, SiteRating>{};
    final sites = [RatingSite.imdb, RatingSite.tmdb, ...RatingSite.external.where(found.containsKey)];

    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(24 * s, phone ? 0 : 24 * s, 24 * s, 24 * s),
      children: [
        Text('Notes', style: VxText.title(20 * s)),
        SizedBox(height: 4 * s),
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: VxText.body(14 * s, color: VxColors.textSecondary),
        ),
        SizedBox(height: 12 * s),
        for (final (i, site) in sites.indexed) ...[
          if (i > 0) const Divider(height: 1, color: VxColors.line),
          _RatingRow(site: site, rating: ratings[site] ?? found[site], scale: s),
        ],
        if (others != null && others.isLoading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12 * s),
            child: Center(
              child: SizedBox.square(dimension: 24 * s, child: const CircularProgressIndicator(strokeWidth: 2.4)),
            ),
          )
        else if (others != null && others.hasError)
          Padding(
            padding: EdgeInsets.only(top: 12 * s),
            child: Text(
              'Les notes des autres sites ne sont pas disponibles pour le moment.',
              style: VxText.body(13 * s, color: VxColors.textSecondary),
            ),
          ),
        if (!phone) ...[
          SizedBox(height: 20 * s),
          VxButton(label: 'Fermer', autofocus: true, expand: true, onPressed: () => Navigator.of(context).pop()),
        ],
      ],
    );
  }
}

/// A site: its logo, its name, its number of votes (when the site gives it) and its rating on its
/// own scale (« 8,8 / 10 », « 79 / 100 »), or « Pas de note » when it doesn't rate the title.
class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.site, required this.rating, required this.scale});

  final RatingSite site;
  final SiteRating? rating;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final rating = this.rating;
    return Semantics(
      container: true,
      label: rating == null
          ? '${site.label} : pas de note'
          : '${site.label} : ${site.format(rating.value)} sur ${site.scale}'
                '${rating.votes > 0 ? ', ${formatVotes(rating.votes)}' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12 * s),
        child: Row(
          children: [
            SizedBox(
              width: 104 * s,
              child: Align(alignment: Alignment.centerLeft, child: RatingLogo(site, size: 18 * s)),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(site.label, style: VxText.body(16 * s, weight: FontWeight.w500)),
                  Text(
                    rating == null ? 'Pas de note' : rating.votes > 0 ? formatVotes(rating.votes) : 'Note MDBList',
                    style: VxText.body(13 * s, color: VxColors.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12 * s),
            if (rating == null)
              Text('–', style: VxText.title(20 * s, color: VxColors.textSecondary))
            else
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: site.format(rating.value), style: VxText.title(20 * s)),
                    TextSpan(text: ' / ${site.scale}', style: VxText.body(13 * s, color: VxColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
