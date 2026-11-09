import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../catalog/models.dart';
import 'rating_dialog.dart';
import 'tmdb.dart';

/// « Mon avis » (`/avis/movie/550`, `/avis/tv/1399?saison=1&episode=2`), opened from a review of
/// « Mes avis »: the title, then its stars and comment to change, and « Supprimer l'avis ». Saving
/// or removing goes back to the list; « Voir la fiche » opens the movie or the TV show.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.target});

  final RatingTarget target;

  /// Where the review of [target] opens.
  static String location(RatingTarget target) => target.isEpisode
      ? '/avis/tv/${target.id}?saison=${target.season}&episode=${target.episode}'
      : '/avis/${target.type.name}/${target.id}';

  /// The review a location names (route parameters).
  static RatingTarget targetOf(Map<String, String> path, Map<String, String> query) {
    final id = int.tryParse(path['id'] ?? '') ?? 0;
    final season = int.tryParse(query['saison'] ?? '');
    final episode = int.tryParse(query['episode'] ?? '');
    return season != null && episode != null
        ? RatingTarget.episode(id, season, episode)
        : RatingTarget.title(MediaType.parse(path['type']), id);
  }

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// The review as last seen: still shown while the page closes after a removal.
  RatedItem? _item;
  bool _saving = false;
  bool _removing = false;

  void _leave() => context.canPop() ? context.pop() : context.go('/avis');

  Future<void> _save(RatedItem item, MyRating rating) async {
    if (rating == item.rating) return _leave();
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tmdbRatingsProvider).rate(widget.target, rating);
      if (!mounted) return;
      _leave();
      showVxSnackOn(messenger, 'Note enregistrée : ${formatScore(rating.value)}/10', icon: Icons.star_rounded);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(RatedItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cet avis ?'),
        content: Text(
          'Votre note de « ${item.label} » sera aussi supprimée sur TMDb, et votre commentaire de Vixeo.',
          style: VxText.body(15, color: VxColors.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          VxButton(
            label: 'Supprimer',
            kind: VxButtonKind.danger,
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _removing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tmdbRatingsProvider).remove(widget.target);
      if (!mounted) return;
      _leave();
      showVxSnackOn(messenger, 'Avis supprimé', icon: Icons.star_outline_rounded);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviews = ref.watch(reviewsProvider);
    final s = uiScale(context);
    _item = reviews.value?.where((i) => i.target == widget.target).firstOrNull ?? _item;
    final item = _item;

    return InfoPage(
      title: 'Mon avis',
      fallback: '/avis',
      children: [
        if (item == null)
          AsyncView(
            value: reviews,
            onRetry: () => ref.invalidate(reviewsProvider),
            data: (_) => const EmptyState(
              icon: Icons.rate_review_outlined,
              title: 'Avis introuvable',
              message: 'Cet avis a peut-être été supprimé, ici ou sur TMDb.',
            ),
          )
        else ...[
          VxCard(child: _ReviewTitle(item: item)),
          SizedBox(height: Layout.of(context).sectionGap),
          VxCard(
            child: RatingForm(
              current: item.rating,
              scale: s,
              saving: _saving,
              onSave: (rating) => _save(item, rating),
              actions: [
                VxButton(
                  label: 'Supprimer l’avis',
                  icon: Icons.delete_outline_rounded,
                  kind: VxButtonKind.danger,
                  expand: true,
                  loading: _removing,
                  onPressed: _saving ? null : () => _remove(item),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Image, title, "Film · 2021" or the episode, the day it was rated, and « Voir la fiche ».
class _ReviewTitle extends StatelessWidget {
  const _ReviewTitle({required this.item});

  final RatedItem item;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final episode = item.type == RatedType.episode;
    final imageWidth = (episode ? 128 : 72) * s;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8 * s),
              child: SizedBox(
                width: imageWidth,
                height: episode ? imageWidth * 9 / 16 : imageWidth * 1.5,
                child: NetImage(url: episode ? (item.stillUrl ?? item.backdropUrl) : item.posterUrl, seed: item.id),
              ),
            ),
            // Between an image and its text.
            SizedBox(width: Layout.of(context).space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: VxText.title(20 * s)),
                  SizedBox(height: 2 * s),
                  Text(item.subtitle, style: VxText.body(14 * s, color: VxColors.textSecondary)),
                  if (item.ratedAt != null) ...[
                    SizedBox(height: 2 * s),
                    Text(
                      'Noté le ${formatFrenchDate(item.ratedAt!)}',
                      style: VxText.body(13 * s, color: VxColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16 * s),
        VxButton(
          label: episode ? 'Voir la série' : 'Voir la fiche',
          icon: Icons.info_outline_rounded,
          kind: VxButtonKind.secondary,
          dense: true,
          onPressed: () => context.push('/titre/${item.mediaType.name}/${item.id}'),
        ),
      ],
    );
  }
}
