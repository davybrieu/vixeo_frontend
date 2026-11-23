import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../library/library.dart';
import '../profiles/profile_preferences_screen.dart';
import '../tmdb/rating_dialog.dart' show showRatingDialog;
import '../tmdb/tmdb.dart';
import 'network.dart';

// The end of a movie or an episode (developer's request, 23/11/2026): the title is marked as
// watched (« Vu », the diary), then a card proposes to rate it, with « Désactiver dans les
// paramètres », which opens « Paramètres du profil » on « Proposer de noter à la fin ».

/// What finished playing: a movie, or an episode ([season], [episode]) of a TV show.
typedef FinishedTitle = ({MediaItem title, int? season, int? episode});

/// Playback is at its end: the last 8 % (5 min at most: the credits) of a video of 3 min or more.
bool atTheEnd(Duration position, Duration duration) {
  if (duration < const Duration(minutes: 3)) return false;
  final credits = Duration(milliseconds: (duration.inMilliseconds * 0.08).round());
  final left = duration - position;
  return left <= (credits > const Duration(minutes: 5) ? const Duration(minutes: 5) : credits);
}

/// Marks [finished] as watched: a movie in « Vu » (and so in the diary), an episode in the diary.
/// A failure changes nothing on screen (the title can still be marked by hand).
Future<void> markFinished(WidgetRef ref, FinishedTitle finished) async {
  final session = ref.read(sessionProvider);
  final profile = session.profile;
  if (!session.isSignedIn || profile == null) return;
  try {
    if (finished.episode == null) {
      await ref.read(libraryProvider.notifier).setWatched(finished.title, true);
    } else {
      await ref.read(libraryProvider.notifier).setEpisodeWatched(
        finished.title,
        season: finished.season!,
        episode: finished.episode!,
      );
      await ref
          .read(networkRepositoryProvider)
          .logViewing(profile.id, finished.title, season: finished.season, episode: finished.episode);
    }
    ref.invalidate(diaryProvider);
  } catch (_) {
    // Not marked: the title page still has « Vu ».
  }
}

/// The rating target of [finished].
RatingTarget ratingTargetOf(FinishedTitle finished) => finished.episode == null
    ? RatingTarget.title(finished.title.type, finished.title.id)
    : RatingTarget.episode(finished.title.id, finished.season!, finished.episode!);

/// Should the card be proposed: a profile that rates, that kept the setting on, and a title (or an
/// episode) not rated yet.
Future<bool> shouldProposeRating(WidgetRef ref, FinishedTitle finished) async {
  final session = ref.read(sessionProvider);
  final profile = session.profile;
  if (!session.isSignedIn || profile == null || !profile.rateAfterWatching || !ref.read(canRateProvider)) {
    return false;
  }
  try {
    return await ref.read(titleRatingProvider(ratingTargetOf(finished)).future) == null;
  } catch (_) {
    return false;
  }
}

/// The card at the end of playback: « Vous avez terminé Dune », « Noter », « Plus tard » and
/// « Désactiver dans les paramètres ». Over the picture, at the bottom right; the video goes on.
class RateAfterWatchingCard extends ConsumerStatefulWidget {
  const RateAfterWatchingCard({super.key, required this.finished, required this.onClose});

  final FinishedTitle finished;
  final VoidCallback onClose;

  @override
  ConsumerState<RateAfterWatchingCard> createState() => _RateAfterWatchingCardState();
}

class _RateAfterWatchingCardState extends ConsumerState<RateAfterWatchingCard> {
  bool _saving = false;

  String get _name {
    final f = widget.finished;
    return f.episode == null ? f.title.title : '${f.title.title} · S${f.season} · É${f.episode}';
  }

  Future<void> _rate() async {
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showRatingDialog(
      context,
      name: _name,
      subtitle: widget.finished.episode == null ? null : 'Épisode ${widget.finished.episode}',
    );
    final rating = choice?.$1;
    if (rating == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(tmdbRatingsProvider).rate(ratingTargetOf(widget.finished), rating);
      showVxSnackOn(messenger, 'Note enregistrée : ${formatScore(rating.value)}/10', icon: Icons.star_rounded);
      ref.invalidate(feedProvider);
      widget.onClose();
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final poster = widget.finished.title.posterUrl;
    return Container(
      width: layout.size(320, tv: 560),
      padding: EdgeInsets.all(layout.space(VxSpace.m)),
      decoration: BoxDecoration(
        color: VxColors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(layout.size(VxRadius.card, tv: VxRadius.cardTv)),
        border: Border.all(color: VxColors.surfaceHigh),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (poster != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(layout.size(8, tv: 12)),
                  child: SizedBox(
                    width: layout.size(44, tv: 72),
                    height: layout.size(66, tv: 108),
                    child: NetImage(url: poster, seed: widget.finished.title.id),
                  ),
                ),
                SizedBox(width: layout.space(VxSpace.s)),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.finished.episode == null ? 'Vous avez terminé' : 'Épisode terminé',
                      style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                    ),
                    Text(
                      _name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.bodySize, weight: FontWeight.w700),
                    ),
                    SizedBox(height: layout.space(VxSpace.xxs)),
                    Text(
                      'Qu’en avez-vous pensé ?',
                      style: VxText.body(layout.captionSize, color: VxColors.textSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: layout.space(VxSpace.s)),
          Row(
            children: [
              Expanded(
                child: VxButton(
                  label: 'Noter',
                  icon: Icons.star_rounded,
                  dense: true,
                  loading: _saving,
                  onPressed: _rate,
                ),
              ),
              SizedBox(width: layout.space(VxSpace.xs)),
              Expanded(
                child: VxButton(label: 'Plus tard', kind: VxButtonKind.outline, dense: true, onPressed: widget.onClose),
              ),
            ],
          ),
          SizedBox(height: layout.space(VxSpace.xs)),
          // The way to the setting (developer's request): « Paramètres du profil », on it.
          VxFocusable(
            borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
            semanticLabel: 'Ne plus proposer de noter : désactiver dans les paramètres',
            // In place of the player (it stays horizontal while open): back returns to the title.
            onPressed: () => context.pushReplacement(ProfilePreferencesScreen.rateAfterWatchingLocation),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.xxs)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.settings_outlined, size: layout.size(16, tv: 26), color: VxColors.textSecondary),
                  SizedBox(width: layout.space(VxSpace.xxs)),
                  Flexible(
                    child: Text(
                      'Désactiver dans les paramètres',
                      style: VxText.body(
                        layout.captionSize,
                        color: VxColors.textSecondary,
                        weight: FontWeight.w600,
                      ).copyWith(decoration: TextDecoration.underline, decorationColor: VxColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
