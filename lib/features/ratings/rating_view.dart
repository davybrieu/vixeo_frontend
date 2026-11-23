import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';

// Ratings shown by the app (vixeo_backend/docs/notes.md): IMDb's (imported by the API from IMDb's
// datasets), else TMDb's, each with its logo. The title page shows both with their votes
// (« Notes », ratings_sheet.dart).

/// A rating and its site: green star, value ("8,8") and the site's logo ([RatingLogo]; TMDb:
/// [TmdbRating]). Read "Note IMDb : 8,8 sur 10" by screen readers.
class RatingLabel extends StatelessWidget {
  const RatingLabel({
    super.key,
    required this.site,
    required this.value,
    this.fontSize = 14,
    this.color = VxColors.text,
  });

  final RatingSite site;
  final double value;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (site == RatingSite.tmdb) return TmdbRating(value, fontSize: fontSize, color: color);
    return Semantics(
      container: true,
      label: 'Note ${site.label} : ${formatRating(value)} sur 10',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: VxColors.accent, size: fontSize * 1.2),
          SizedBox(width: fontSize * 0.25),
          Text(formatRating(value), style: VxText.body(fontSize, color: color, weight: FontWeight.w600)),
          SizedBox(width: fontSize * 0.45),
          RatingLogo(site, size: fontSize),
        ],
      ),
    );
  }
}

/// The logo of a rating's site, next to a text of [size] (`RatingSite.logoHeight`: wide logos
/// lower, square ones higher): `assets/images/ratings/<site>.png` (from `brand/ratings`), TMDb's
/// official one ([TmdbLogo]). Not read by screen readers: the rating's label names the site.
class RatingLogo extends StatelessWidget {
  const RatingLogo(this.site, {super.key, required this.size});

  final RatingSite site;
  final double size;

  @override
  Widget build(BuildContext context) {
    final height = size * site.logoHeight;
    if (site == RatingSite.tmdb) return TmdbLogo(height: height);
    return Image.asset(
      site.logoAsset,
      height: height,
      width: height * site.logoAspect,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
  }
}

/// The rating under a phone card, on the right of the year (IMDb's when given with the title, else
/// TMDb's): shrunk rather than cut on a narrow card. An [Expanded]: a child of the caption's [Row].
class CardRating extends StatelessWidget {
  const CardRating({super.key, required this.item, this.fontSize = 11, this.color = VxColors.textSecondary});

  final MediaItem item;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final shown = item.shownRating;
    if (shown == null) return const Spacer();
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: RatingLabel(site: shown.$1, value: shown.$2.value, fontSize: fontSize, color: color),
      ),
    );
  }
}
