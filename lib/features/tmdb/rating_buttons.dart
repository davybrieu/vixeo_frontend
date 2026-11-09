import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import 'rating_dialog.dart';
import 'tmdb.dart';

/// "Noter" on a movie or TV show page: the same round icon-only button as Ma liste / Vu, filled
/// when rated. Only when a TMDb account is linked ([canRateProvider]).
class RateTitleButton extends ConsumerWidget {
  const RateTitleButton({super.key, required this.type, required this.id, required this.name});

  final MediaType type;
  final int id;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = RatingTarget.title(type, id);
    final rating = ref.watch(titleRatingProvider(target)).value;
    return VxIconAction(
      icon: rating == null ? Icons.star_outline_rounded : Icons.star_rounded,
      label: rating == null ? 'Noter' : 'Ma note : ${formatScore(rating.value)} sur 10, modifier',
      active: rating != null,
      onPressed: () => editRating(context, target: target, name: name, current: rating),
    );
  }
}

/// "Noter l'épisode", at the end of an episode row.
class RateEpisodeButton extends StatelessWidget {
  const RateEpisodeButton({super.key, required this.target, required this.showName, required this.episode, this.value});

  final RatingTarget target;
  final String showName;
  final Episode episode;

  /// The profile's rating and comment, null when not rated.
  final MyRating? value;

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
      name: episode.name,
      subtitle: '$showName · Saison ${episode.seasonNumber}, épisode ${episode.number}',
      current: value,
    ),
  );
}
