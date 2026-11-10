import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import '../catalog/models.dart';
import '../tv/models.dart';
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

/// Adds to « Favoris » (❤), or removes, then confirms with an alert. [write] does the change.
Future<void> _toggleLiked(
  BuildContext context,
  bool wasLiked,
  Future<void> Function(LibraryController, bool) write,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await write(container.read(libraryProvider.notifier), !wasLiked);
    if (context.mounted) {
      showVxSnack(
        context,
        wasLiked ? 'Supprimé de vos favoris' : 'Ajouté à vos favoris',
        icon: wasLiked ? Icons.heart_broken_rounded : Icons.favorite_rounded,
      );
    }
  } catch (e) {
    if (context.mounted) showVxSnack(context, '$e', icon: Icons.error_outline_rounded);
  }
}

/// « Favoris » of a movie or a TV show.
Future<void> toggleLiked(BuildContext context, MediaItem item) {
  final liked = ProviderScope.containerOf(context, listen: false).read(libraryProvider).value?.forItem(item)?.isLiked;
  return _toggleLiked(context, liked ?? false, (library, value) => library.setLiked(item, value));
}

/// « Favoris » of an episode of [show].
Future<void> toggleEpisodeLiked(BuildContext context, MediaItem show, Episode episode) {
  final liked = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(libraryProvider).value?.forEpisode(show.id, episode.seasonNumber, episode.number)?.isLiked;
  return _toggleLiked(context, liked ?? false, (library, value) => library.setEpisodeLiked(show, episode, value));
}

/// « Favoris » of a live channel.
Future<void> toggleChannelLiked(BuildContext context, TvChannel channel) {
  final liked = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(libraryProvider).value?.forChannel(channel)?.isLiked;
  return _toggleLiked(context, liked ?? false, (library, value) => library.setChannelLiked(channel, value));
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

/// « Favoris » (❤) toggle, the same round icon-only button everywhere: [liked] is the current state.
class LikeButton extends StatelessWidget {
  const LikeButton({super.key, required this.liked, required this.onPressed, this.dense = false});

  final bool liked;
  final VoidCallback onPressed;

  /// Smaller, in a list row (episodes).
  final bool dense;

  @override
  Widget build(BuildContext context) => VxIconAction(
    icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
    label: liked ? 'Retirer des favoris' : 'Ajouter aux favoris',
    active: liked,
    dense: dense,
    onPressed: onPressed,
  );
}

/// « Favoris » of a movie or a TV show (title page, hero).
class LikedButton extends ConsumerWidget {
  const LikedButton({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(libraryProvider).value?.forItem(item)?.isLiked ?? false;
    return LikeButton(liked: liked, onPressed: () => toggleLiked(context, item));
  }
}

/// « Favoris » of an episode, at the end of its row.
class EpisodeLikedButton extends ConsumerWidget {
  const EpisodeLikedButton({super.key, required this.show, required this.episode});

  final MediaItem show;
  final Episode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked =
        ref.watch(libraryProvider).value?.forEpisode(show.id, episode.seasonNumber, episode.number)?.isLiked ?? false;
    return LikeButton(liked: liked, dense: true, onPressed: () => toggleEpisodeLiked(context, show, episode));
  }
}

/// « Favoris » of a live channel (player).
class ChannelLikedButton extends ConsumerWidget {
  const ChannelLikedButton({super.key, required this.channel});

  final TvChannel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(libraryProvider).value?.forChannel(channel)?.isLiked ?? false;
    return LikeButton(liked: liked, onPressed: () => toggleChannelLiked(context, channel));
  }
}
