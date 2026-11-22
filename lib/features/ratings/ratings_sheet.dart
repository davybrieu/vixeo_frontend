import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'rating_view.dart';

class RatingButton extends StatelessWidget {
  const RatingButton({
    super.key,
    required this.ratings,
    required this.name,
    this.type = MediaType.movie,
    this.id = 0,
    this.fontSize = 14,
  });

  final TitleRatings ratings;
  final String name;
  final MediaType type;
  final int id;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final shown = ratings.shown;
    if (shown == null) return const SizedBox.shrink();
    final (site, rating) = shown;
    return VxFocusable(
      borderRadius: fontSize * 0.5,
      semanticLabel: 'Note ${site.label} : ${formatRating(rating.value)} sur 10. Voir les notes',
      onPressed: () => showAllRatings(context, ratings: ratings, name: name, type: type, id: id),
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

Future<void> showAllRatings(
  BuildContext context, {
  required TitleRatings ratings,
  required String name,
  required MediaType type,
  required int id,
}) {
  final layout = Layout.of(context);
  final content = _AllRatings(ratings: ratings, name: name, type: type, id: id);
  if (layout.isPhone) {
    return showModalBottomSheet<void>(
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
  const _AllRatings({required this.ratings, required this.name, required this.type, required this.id});

  final TitleRatings ratings;
  final String name;
  final MediaType type;
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final phone = layout.isPhone;
    final s = layout.isLarge ? layout.tv(1) * 1.6 : 1.0;
    // The provider is first watched here: no MDBList request before opening this modal.
    final external = id > 0
        ? ref.watch(externalRatingsProvider((type, id)))
        : const AsyncValue<Map<String, SiteRating>>.data({});
    final extra = external.asData?.value ?? const <String, SiteRating>{};
    final sites = <RatingSite>[
      RatingSite.imdb,
      RatingSite.tmdb,
      for (final site in RatingSite.values.skip(2))
        if (_externalRating(site, extra) != null) site,
    ];

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
          _RatingRow(site: site, rating: ratings[site] ?? _externalRating(site, extra), scale: s),
        ],
        if (external.isLoading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12 * s),
            child: const Center(child: CircularProgressIndicator()),
          ),
        if (external.hasError)
          Text('Notes supplémentaires indisponibles pour le moment.',
              style: VxText.body(12 * s, color: VxColors.textSecondary)),
        if (!phone) ...[
          SizedBox(height: 20 * s),
          VxButton(label: 'Fermer', autofocus: true, expand: true, onPressed: () => Navigator.of(context).pop()),
        ],
      ],
    );
  }
}

SiteRating? _externalRating(RatingSite site, Map<String, SiteRating> ratings) => switch (site) {
  RatingSite.trakt => ratings['trakt'],
  RatingSite.letterboxd => ratings['letterboxd'],
  RatingSite.tomatoes => ratings['tomatoes'],
  RatingSite.audience => ratings['audience'],
  RatingSite.metacritic => ratings['metacritic'],
  RatingSite.mal => ratings['mal'],
  _ => null,
};

String _scaleLabel(RatingSite site) => switch (site) {
  RatingSite.letterboxd => '/ 5',
  RatingSite.tomatoes || RatingSite.audience || RatingSite.metacritic || RatingSite.trakt => '/ 100',
  _ => '/ 10',
};

class _RatingRow extends StatelessWidget {
  const _RatingRow({required this.site, required this.rating, required this.scale});

  final RatingSite site;
  final SiteRating? rating;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final rating = this.rating;
    final scaleLabel = _scaleLabel(site);
    return Semantics(
      container: true,
      label: rating == null
          ? '${site.label} : pas de note'
          : '${site.label} : ${formatRating(rating.value)} sur ${scaleLabel.substring(2)}'
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
                    TextSpan(text: formatRating(rating.value), style: VxText.title(20 * s)),
                    TextSpan(text: ' $scaleLabel', style: VxText.body(13 * s, color: VxColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
