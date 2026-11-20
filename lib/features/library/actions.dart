import 'package:material_ui/material_ui.dart';
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

/// Adds the title to « Favoris » ❤, or removes it, then confirms with an alert.
Future<void> toggleLiked(BuildContext context, MediaItem item) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final wasLiked = container.read(libraryProvider).value?.forItem(item)?.isLiked ?? false;
  try {
    await container.read(libraryProvider.notifier).setLiked(item, !wasLiked);
    if (context.mounted) {
      showVxSnack(
        context,
        wasLiked ? 'Retiré de vos favoris' : 'Ajouté à vos favoris',
        icon: wasLiked ? Icons.heart_broken_outlined : Icons.favorite_rounded,
      );
    }
  } catch (e) {
    if (context.mounted) showVxSnack(context, '$e', icon: Icons.error_outline_rounded);
  }
}

/// Follows a person (actor, director…), or no longer, then confirms with an alert.
Future<void> toggleFollowed(BuildContext context, Person person) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final wasFollowed = container.read(libraryProvider).value?.forPerson(person.id)?.isFollowed ?? false;
  try {
    await container.read(libraryProvider.notifier).setFollowed(person, !wasFollowed);
    if (context.mounted) {
      showVxSnack(
        context,
        wasFollowed ? 'Vous ne suivez plus ${person.name}' : 'Vous suivez ${person.name}',
        icon: wasFollowed ? Icons.person_remove_outlined : Icons.person_add_alt_1_rounded,
      );
    }
  } catch (e) {
    if (context.mounted) showVxSnack(context, '$e', icon: Icons.error_outline_rounded);
  }
}

/// « Favoris » ❤ toggle: the same round icon-only button as Ma liste and Vu.
class LikedButton extends ConsumerWidget {
  const LikedButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(libraryProvider).value?.forItem(item)?.isLiked ?? false;
    return VxIconAction(
      icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      label: liked ? 'Retirer des favoris' : 'Ajouter aux favoris',
      active: liked,
      onPressed: () => toggleLiked(context, item),
    );
  }
}

/// « Suivre » / « Ne plus suivre » on a person's page.
class FollowPersonButton extends ConsumerStatefulWidget {
  const FollowPersonButton({super.key, required this.person});

  final Person person;

  @override
  ConsumerState<FollowPersonButton> createState() => _FollowPersonButtonState();
}

class _FollowPersonButtonState extends ConsumerState<FollowPersonButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    await toggleFollowed(context, widget.person);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final followed = ref.watch(libraryProvider).value?.forPerson(widget.person.id)?.isFollowed ?? false;
    return VxButton(
      label: followed ? 'Ne plus suivre' : 'Suivre',
      icon: followed ? Icons.person_remove_outlined : Icons.person_add_alt_1_rounded,
      kind: followed ? VxButtonKind.secondary : VxButtonKind.primary,
      dense: true,
      loading: _busy,
      onPressed: _toggle,
    );
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
