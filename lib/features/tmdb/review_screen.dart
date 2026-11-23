import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'rating_form.dart';
import 'tmdb.dart';

/// What the page « Noter » shows of a title before any request, and the rating its caller knows:
/// passed with the route (`extra`), never in the address.
@immutable
class RatingSubject {
  const RatingSubject({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.wide = false,
    this.ratedAt,
    this.current,
    this.titleLink = true,
  });

  /// A review of « Mes avis » (or of the feed): everything is known.
  factory RatingSubject.of(RatedItem item) {
    final episode = item.type == RatedType.episode;
    return RatingSubject(
      title: item.title,
      subtitle: item.subtitle,
      imageUrl: episode ? (item.stillUrl ?? item.backdropUrl) : item.posterUrl,
      wide: episode,
      ratedAt: item.ratedAt,
      current: item.rating,
    );
  }

  final String title;

  /// « Film · 2021 », « Saison 1, épisode 2 · La route ».
  final String? subtitle;
  final String? imageUrl;

  /// A 16:9 image (an episode), rather than a poster.
  final bool wide;
  final DateTime? ratedAt;

  /// The profile's rating and comment, null when not rated yet.
  final MyRating? current;

  /// « Voir la fiche »: not when the page was opened from the title page itself.
  final bool titleLink;
}

/// Opens the page to rate [target], or to change or remove its rating (no dialog: developer's
/// request, 23/11/2026). Returns `(rating,)` when saved, `(null,)` when removed, null when left
/// without a change. The page saves itself and confirms with an alert.
Future<(MyRating?,)?> editRating(BuildContext context, {required RatingTarget target, required RatingSubject subject}) =>
    context.push<(MyRating?,)>(ReviewScreen.location(target), extra: subject);

/// « Noter » / « Mon avis » (`/avis/movie/550`, `/avis/tv/1399?saison=1&episode=2`): the page where a
/// movie, a TV show or an episode is rated (developer's request, 23/11/2026: a page, not a
/// dialog), from the title page, an episode, the end of playback, the first launch or « Mes
/// avis »: the title, then its stars, its comment and « Contient des spoilers », « Enregistrer »
/// and, when rated, « Supprimer ». Saving or removing goes back where it came from.
///
/// [subject] (`extra` of the route) gives the title and the rating at once; without it (an address
/// typed or from a notification), the page asks for the rating and the title.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.target, this.subject});

  final RatingTarget target;
  final RatingSubject? subject;

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
  bool _saving = false;
  bool _removing = false;

  void _leave([(MyRating?,)? result]) => context.canPop() ? context.pop(result) : context.go('/avis');

  Future<void> _save(MyRating? current, MyRating rating) async {
    if (rating == current) return _leave();
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tmdbRatingsProvider).rate(widget.target, rating);
      if (!mounted) return;
      _leave((rating,));
      showVxSnackOn(messenger, 'Note enregistrée : ${formatScore(rating.value)}/10', icon: Icons.star_rounded);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(String name) async {
    final ok = await showVxConfirm(
      context,
      title: 'Supprimer cet avis ?',
      message: 'Votre note et votre commentaire de « $name » seront supprimés.',
      confirm: 'Supprimer',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _removing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tmdbRatingsProvider).remove(widget.target);
      if (!mounted) return;
      _leave((null,));
      showVxSnackOn(messenger, 'Avis supprimé', icon: Icons.star_outline_rounded);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  /// The title without [RatingSubject]: from the title page (one request, often already cached).
  RatingSubject _subjectOf(TitleDetails? details) {
    final target = widget.target;
    final item = details?.asItem;
    final kind = target.type == MediaType.movie ? 'Film' : 'Série';
    return RatingSubject(
      title: item?.title ?? '',
      subtitle: target.isEpisode
          ? 'Saison ${target.season}, épisode ${target.episode}'
          : [kind, if (item?.year != null) '${item!.year}'].join(' · '),
      imageUrl: target.isEpisode ? item?.backdropUrl : item?.posterUrl,
      wide: target.isEpisode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target;
    final given = widget.subject;
    final subject = given ?? _subjectOf(ref.watch(titleProvider((target.type, target.id))).value);
    // The caller knows the rating; otherwise one request.
    final AsyncValue<MyRating?> rating = given != null ? AsyncData(given.current) : ref.watch(myRatingProvider(target));
    final current = rating.value;
    final s = uiScale(context);

    return InfoPage(
      title: rating.hasValue && current == null ? 'Noter' : 'Mon avis',
      fallback: '/avis',
      children: [
        VxCard(
          child: _ReviewTitle(
            subject: subject,
            target: target,
          ),
        ),
        SizedBox(height: Layout.of(context).sectionGap),
        if (!rating.hasValue)
          rating.hasError
              ? ErrorPanel(error: rating.error!, onRetry: () => ref.invalidate(myRatingProvider(target)))
              : const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else
          VxCard(
            child: RatingForm(
              // A new form when the rating arrives (typed address).
              key: ValueKey(current),
              current: current,
              scale: s,
              saving: _saving,
              onSave: (value) => _save(current, value),
              actions: [
                if (current != null)
                  VxButton(
                    label: 'Supprimer',
                    icon: Icons.delete_outline_rounded,
                    kind: VxButtonKind.danger,
                    expand: true,
                    loading: _removing,
                    onPressed: _saving ? null : () => _remove(subject.title),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Image, title, "Film · 2021" or the episode, the day it was rated, and « Voir la fiche ».
class _ReviewTitle extends StatelessWidget {
  const _ReviewTitle({required this.subject, required this.target});

  final RatingSubject subject;
  final RatingTarget target;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final wide = subject.wide;
    final imageWidth = (wide ? 128 : 72) * s;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8 * s),
              child: SizedBox(
                width: imageWidth,
                height: wide ? imageWidth * 9 / 16 : imageWidth * 1.5,
                child: NetImage(url: subject.imageUrl, seed: target.id),
              ),
            ),
            // Between an image and its text.
            SizedBox(width: Layout.of(context).space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subject.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: VxText.title(20 * s)),
                  if ((subject.subtitle ?? '').isNotEmpty) ...[
                    SizedBox(height: 2 * s),
                    Text(subject.subtitle!, style: VxText.body(14 * s, color: VxColors.textSecondary)),
                  ],
                  if (subject.ratedAt != null) ...[
                    SizedBox(height: 2 * s),
                    Text(
                      'Noté le ${formatFrenchDate(subject.ratedAt!)}',
                      style: VxText.body(13 * s, color: VxColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (subject.titleLink) ...[
          SizedBox(height: 16 * s),
          VxButton(
            label: target.isEpisode ? 'Voir la série' : 'Voir la fiche',
            icon: Icons.info_outline_rounded,
            kind: VxButtonKind.secondary,
            dense: true,
            onPressed: () => context.push('/titre/${target.type.name}/${target.id}'),
          ),
        ],
      ],
    );
  }
}
