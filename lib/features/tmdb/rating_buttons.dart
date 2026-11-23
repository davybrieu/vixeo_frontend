import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import 'review_screen.dart';
import 'tmdb.dart';

/// "Noter" on a movie or TV show page: the same round icon-only button as À voir / Vu, filled
/// when rated; it opens the page « Noter » / « Mon avis » (no dialog). For every signed-in profile
/// ([canRateProvider]).
class RateTitleButton extends ConsumerWidget {
  const RateTitleButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = RatingTarget.title(item.type, item.id);
    final rating = ref.watch(titleRatingProvider(target)).value;
    return VxIconAction(
      icon: rating == null ? Icons.star_outline_rounded : Icons.star_rounded,
      label: rating == null ? 'Noter' : 'Ma note : ${formatScore(rating.value)} sur 10, modifier',
      active: rating != null,
      onPressed: () => editRating(
        context,
        target: target,
        subject: RatingSubject(
          title: item.title,
          subtitle: [item.type == MediaType.movie ? 'Film' : 'Série', if (item.year != null) '${item.year}'].join(' · '),
          imageUrl: item.posterUrl,
          current: rating,
          titleLink: false,
        ),
      ),
    );
  }
}

/// "Noter l'épisode", on an episode card: the page « Noter » of the episode.
class RateEpisodeButton extends StatelessWidget {
  const RateEpisodeButton({
    super.key,
    required this.target,
    required this.showName,
    required this.episode,
    this.value,
    this.imageUrl,
  });

  final RatingTarget target;
  final String showName;
  final Episode episode;

  /// The profile's rating and comment, null when not rated.
  final MyRating? value;

  /// The episode's image, or the show's.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => VxIconAction(
    dense: true,
    icon: value == null ? Icons.star_outline_rounded : Icons.star_rounded,
    label: value == null
        ? 'Noter l’épisode ${episode.number}'
        : 'Ma note de l’épisode ${episode.number} : ${formatScore(value!.value)} sur 10, modifier',
    active: value != null,
    onPressed: () => editRating(
      context,
      target: target,
      subject: RatingSubject(
        title: episode.name.isEmpty ? 'Épisode ${episode.number}' : episode.name,
        subtitle: '$showName · Saison ${episode.seasonNumber}, épisode ${episode.number}',
        imageUrl: episode.stillUrl ?? imageUrl,
        wide: true,
        current: value,
        titleLink: false,
      ),
    ),
  );
}
