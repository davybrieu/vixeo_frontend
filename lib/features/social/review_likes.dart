import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../auth/session.dart';
import '../tmdb/tmdb.dart';
import 'social_repository.dart';

/// « J'aime » on another member's review (developer's request, 21/11/2026, like Twitter; API:
/// vixeo_backend/docs/social.md). The reviews come with `liked` and `likes_count`; what the active
/// profile changes since is kept here, by review id, so a list read again or a row built again
/// shows it at once. Forgotten when the profile changes.
final reviewLikesProvider = NotifierProvider<ReviewLikes, Map<int, ReviewLikeState>>(ReviewLikes.new);

class ReviewLikes extends Notifier<Map<int, ReviewLikeState>> {
  @override
  Map<int, ReviewLikeState> build() {
    ref.watch(sessionProvider.select((s) => s.profile?.id));
    return const {};
  }

  /// Liked or not, and the number of likes, of [review] as the active profile sees it now.
  ReviewLikeState of(RatedItem review) =>
      state[review.reviewId] ?? (liked: review.liked, likesCount: review.likesCount);

  /// Likes or unlikes [review]: shown at once, then the API's count (or back, on a failure, which
  /// is thrown).
  Future<void> toggle(RatedItem review) async {
    final id = review.reviewId;
    if (id == null) return;
    final before = of(review);
    final liked = !before.liked;
    state = {...state, id: (liked: liked, likesCount: math.max(0, before.likesCount + (liked ? 1 : -1)))};
    try {
      final after = await ref.read(socialRepositoryProvider).likeReview(id, liked: liked);
      if (ref.mounted) state = {...state, id: after};
    } catch (_) {
      if (ref.mounted) state = {...state, id: before};
      rethrow;
    }
  }
}

/// The heart of another member's review and its number of likes. A guest is asked to sign in.
class ReviewLikeButton extends ConsumerStatefulWidget {
  const ReviewLikeButton({super.key, required this.review});

  final RatedItem review;

  @override
  ConsumerState<ReviewLikeButton> createState() => _ReviewLikeButtonState();
}

class _ReviewLikeButtonState extends ConsumerState<ReviewLikeButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final session = ref.read(sessionProvider);
    if (!session.isSignedIn || session.profile == null) {
      showVxSnackOn(messenger, 'Connectez-vous pour aimer un avis.', icon: Icons.login_rounded);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(reviewLikesProvider.notifier).toggle(widget.review);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    } catch (_) {
      showVxSnackOn(messenger, 'Impossible de modifier le J’aime.', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final state = ref.watch(reviewLikesProvider.select((likes) => likes[widget.review.reviewId])) ??
        (liked: widget.review.liked, likesCount: widget.review.likesCount);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        VxIconAction(
          icon: state.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          label: state.liked ? 'Je n’aime plus cet avis' : 'J’aime cet avis',
          active: state.liked,
          dense: true,
          onPressed: _toggle,
        ),
        SizedBox(height: layout.space(VxSpace.xxs) / 2),
        Text(
          state.likesCount > 0 ? '${state.likesCount}' : ' ',
          semanticsLabel: likesLabel(state.likesCount),
          style: VxText.body(layout.captionSize, color: state.liked ? VxColors.accent : VxColors.textSecondary),
        ),
      ],
    );
  }
}

/// "1 J'aime", "3 J'aime" (invariable), "Aucun J'aime".
String likesLabel(int count) => count == 0 ? 'Aucun J’aime' : '$count J’aime';
