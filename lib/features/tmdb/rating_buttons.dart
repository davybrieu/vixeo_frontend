import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import 'rating_dialog.dart';
import 'tmdb.dart';

/// "Noter" on a movie or TV show page: the same round icon-only button as Ma liste / Vu, filled
/// when rated. For every signed-in profile ([canRateProvider]).
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
