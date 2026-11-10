import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import 'library.dart';

/// Adds the title to the profile's list, or removes it, then confirms with an alert.
Future<void> toggleFavorite(BuildContext context, MediaItem item) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final wasFavorite = container.read(libraryProvider).value?.forItem(item)?.isFavorite ?? false;
  try {
    await container.read(libraryProvider.notifier).setFavorite(item, !wasFavorite);
    if (context.mounted) {
      showVxSnack(
        context,
        wasFavorite ? 'Supprimé de votre liste' : 'Ajouté à votre liste',
        icon: wasFavorite ? Icons.bookmark_remove_rounded : Icons.bookmark_added_rounded,
      );
    }
  } catch (e) {
    if (context.mounted) showVxSnack(context, '$e', icon: Icons.error_outline_rounded);
  }
}

/// Marks the title as watched, or not watched, then confirms with an alert.
Future<void> toggleWatched(BuildContext context, MediaItem item) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final wasWatched = container.read(libraryProvider).value?.forItem(item)?.isWatched ?? false;
  try {
    await container.read(libraryProvider.notifier).setWatched(item, !wasWatched);
    if (context.mounted) {
      showVxSnack(
        context,
        wasWatched ? 'Marqué comme non vu' : 'Marqué comme vu',
        icon: wasWatched ? Icons.remove_done_rounded : Icons.check_circle_rounded,
      );
    }
  } catch (e) {
    if (context.mounted) showVxSnack(context, '$e', icon: Icons.error_outline_rounded);
  }
}

/// Ma liste toggle: the same round icon-only button everywhere.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorite = ref.watch(libraryProvider).value?.forItem(item)?.isFavorite ?? false;
    return VxIconAction(
      icon: favorite ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
      label: favorite ? 'Retirer de ma liste' : 'Ajouter à ma liste',
      active: favorite,
      onPressed: () => toggleFavorite(context, item),
    );
  }
}

/// Vu / non vu toggle.
class WatchedButton extends ConsumerWidget {
  const WatchedButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref.watch(libraryProvider).value?.forItem(item)?.isWatched ?? false;
    return VxIconAction(
      icon: watched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
      label: watched ? 'Marquer comme non vu' : 'Marquer comme vu',
      active: watched,
      onPressed: () => toggleWatched(context, item),
    );
  }
}
