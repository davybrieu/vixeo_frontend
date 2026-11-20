import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import 'ratings.dart';

/// The rating a title shows with the profile's site (« Source des notes »): [ShownRating.waiting]
/// while its ratings are asked. TMDb needs no request (its rating comes with the title).
ShownRating watchShownRating(WidgetRef ref, TitleRef title, double tmdb) {
  final source = ref.watch(ratingSourceProvider);
  if (source == RatingSource.tmdb) return ShownRating.pick(source, null, tmdb);
  final ratings = ref.watch(titleRatingsProvider(title));
  if (!ratings.hasValue) return ShownRating.waiting;
  return ShownRating.pick(source, ratings.value, tmdb);
}

/// Asks the ratings of a row or page of cards in one request (cards built later then find them).
/// Nothing to ask when the profile shows TMDb's rating.
void prefetchRatings(WidgetRef ref, Iterable<MediaItem> items) {
  if (ref.watch(ratingSourceProvider) == RatingSource.tmdb) return;
  ref.read(ratingsLoaderProvider).prefetch([for (final item in items) (type: item.type, id: item.id)]);
}

/// A rating and its site: green star, value ("8,8", "79 %") and the site's tag ("IMDb"; TMDb's
/// logo for TMDb, [TmdbRating]). Read "Note IMDb : 8,8 sur 10" by screen readers.
class RatingLabel extends StatelessWidget {
  const RatingLabel({
    super.key,
    required this.source,
    required this.value,
    this.fontSize = 14,
    this.color = VxColors.text,
  });

  final RatingSource source;
  final double value;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (source == RatingSource.tmdb) return TmdbRating(value, fontSize: fontSize, color: color);
    return Semantics(
      container: true,
      label: 'Note ${source.label} : ${source.spoken(value)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: VxColors.accent, size: fontSize * 1.2),
          SizedBox(width: fontSize * 0.25),
          Text(source.format(value), style: VxText.body(fontSize, color: color, weight: FontWeight.w600)),
          SizedBox(width: fontSize * 0.45),
          RatingTag(source, fontSize: fontSize * 0.68),
        ],
      ),
    );
  }
}

/// Short name of a rating's site in its colours ("IMDb" in black on yellow…), [fontSize] high.
class RatingTag extends StatelessWidget {
  const RatingTag(this.source, {super.key, required this.fontSize});

  final RatingSource source;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: fontSize * 0.4, vertical: fontSize * 0.12),
    decoration: BoxDecoration(color: source.tagColor, borderRadius: BorderRadius.circular(fontSize * 0.3)),
    child: Text(
      source.tag,
      style: VxText.body(fontSize, color: source.tagTextColor, weight: FontWeight.w800, height: 1.15),
    ),
  );
}

/// The rating under a phone card, on the right of the year: shrunk rather than cut on a narrow
/// card. An [Expanded]: a child of the caption's [Row].
class CardRating extends ConsumerWidget {
  const CardRating({super.key, required this.item, this.fontSize = 11, this.color = VxColors.textSecondary});

  final MediaItem item;
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = watchShownRating(ref, (type: item.type, id: item.id), item.voteAverage);
    if (shown.isNone) return const Spacer();
    return Expanded(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: RatingLabel(source: shown.source!, value: shown.value!, fontSize: fontSize, color: color),
      ),
    );
  }
}
