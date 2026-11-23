import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../notifications/inbox.dart' show socialAvailable;
import '../tmdb/rating_dialog.dart' show showRatingDialog;
import '../tmdb/tmdb.dart';
import 'feed_screen.dart' show SuggestionCard;
import 'network.dart';
import 'widgets.dart';

/// The first launch of a new profile (`/bienvenue`, vixeo_backend/docs/social.md): rate a few
/// titles already seen (they shape the suggestions and the « goûts en commun »), then accounts to
/// follow. « Passer » at any time; once done or skipped, it never comes back (`onboarded`).
/// Not on a TV, nor for a child's profile.
///
/// Flutter: a page in two steps, like a wizard in Vue: one state ([_step]) chooses what is drawn.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  static const location = '/bienvenue';

  /// The router opens this page after « Qui regarde ? » when the profile hasn't seen it yet.
  static bool needed(SessionState session) =>
      socialAvailable(session) && !DeviceInfo.isTv && session.profile?.onboarded == false;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _finishing = false;

  /// What was rated here: `movie:550` → the rating.
  final _rated = <String, double>{};

  Future<void> _rate(MediaItem title) async {
    final key = itemIdOf(title.type, title.id);
    final current = _rated[key];
    final choice = await showRatingDialog(
      context,
      name: title.title,
      subtitle: title.year == null ? null : '${title.year}',
      current: current == null ? null : MyRating(current),
    );
    if (choice == null || !mounted) return;
    final (rating,) = choice;
    final messenger = ScaffoldMessenger.of(context);
    final target = RatingTarget.title(title.type, title.id);
    try {
      if (rating == null) {
        await ref.read(tmdbRatingsProvider).remove(target);
        if (mounted) setState(() => _rated.remove(key));
      } else {
        await ref.read(tmdbRatingsProvider).rate(target, rating);
        if (mounted) setState(() => _rated[key] = rating.value);
      }
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    }
  }

  /// Done or skipped: never again for this profile, then the home page.
  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    final router = GoRouter.of(context);
    final profile = ref.read(sessionProvider).profile;
    if (profile != null) {
      try {
        final updated = await ref.read(authRepositoryProvider).updateProfile(profile.id, {'onboarded': true});
        ref.read(sessionProvider.notifier).updateProfile(updated);
      } catch (_) {
        // Asked again at the next launch: nothing is lost.
      }
    }
    ref.invalidate(feedProvider);
    router.go('/accueil');
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final name = ref.watch(sessionProvider.select((s) => s.profile?.name)) ?? '';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.s), layout.gutter, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 2; i++)
                    Container(
                      width: layout.size(28, tv: 44),
                      height: layout.size(4, tv: 6),
                      margin: EdgeInsets.only(right: layout.space(VxSpace.xxs)),
                      decoration: BoxDecoration(
                        color: i <= _step ? VxColors.accent : VxColors.line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  VxButton(label: 'Passer', kind: VxButtonKind.outline, dense: true, onPressed: _finish),
                ],
              ),
            ),
            Expanded(child: _step == 0 ? _rateStep(layout, name) : _followStep(layout)),
            Padding(
              padding: EdgeInsets.fromLTRB(
                layout.gutter,
                layout.space(VxSpace.s),
                layout.gutter,
                layout.space(VxSpace.m) + MediaQuery.paddingOf(context).bottom,
              ),
              child: VxButton(
                label: _step == 0
                    ? (_rated.isEmpty ? 'Continuer' : 'Continuer (${_rated.length} ${_rated.length > 1 ? 'notés' : 'noté'})')
                    : 'Terminer',
                icon: _step == 0 ? Icons.arrow_forward_rounded : Icons.check_rounded,
                expand: true,
                loading: _finishing,
                onPressed: _step == 0 ? () => setState(() => _step = 1) : _finish,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Step 1: popular titles to rate (a press opens the stars).
  Widget _rateStep(Layout layout, String name) {
    final home = ref.watch(homeProvider);
    final seen = <String>{};
    final titles = [
      for (final section in home.value?.sections ?? const <Section>[])
        for (final item in section.items)
          if (seen.add(itemIdOf(item.type, item.id))) item,
    ].take(30).toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.l), layout.gutter, layout.space(VxSpace.m)),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Bienvenue sur Vixeo' : 'Bienvenue, $name',
                  style: VxText.title(layout.pageTitleSize),
                ),
                SizedBox(height: layout.space(VxSpace.xs)),
                Text(
                  'Notez quelques films ou séries que vous avez vus : vos avis apparaîtront sur votre page et '
                  'Vixeo trouvera les membres qui ont les mêmes goûts que vous.',
                  style: VxText.body(layout.bodySize, color: VxColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        if (titles.isEmpty)
          SliverToBoxAdapter(
            child: NetworkLoading(error: home.error, onRetry: () => ref.invalidate(homeProvider)),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.space(VxSpace.m)),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: layout.size(120, tv: 200),
                mainAxisSpacing: layout.cardGap,
                crossAxisSpacing: layout.cardGap,
                childAspectRatio: 2 / 3,
              ),
              delegate: SliverChildBuilderDelegate(childCount: titles.length, (context, i) {
                final title = titles[i];
                final rating = _rated[itemIdOf(title.type, title.id)];
                return VxFocusable(
                  borderRadius: layout.size(VxRadius.poster, tv: 16),
                  semanticLabel: rating == null
                      ? '${title.title}, noter'
                      : '${title.title}, noté ${formatScore(rating)} sur 10, modifier',
                  onPressed: () => _rate(title),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(layout.size(VxRadius.poster, tv: 16)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(url: title.posterUrl, seed: title.id),
                        if (rating != null)
                          ColoredBox(
                            color: Colors.black54,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star_rounded, color: VxColors.accent, size: layout.size(28, tv: 44)),
                                  Text(
                                    formatScore(rating),
                                    style: VxText.title(layout.size(20, tv: 32), color: VxColors.text),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  /// Step 2: accounts to follow.
  Widget _followStep(Layout layout) {
    final suggestions = ref.watch(suggestionsProvider);
    final value = suggestions.value;
    return ListView(
      padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.l), layout.gutter, layout.space(VxSpace.m)),
      children: [
        Text('Suivez des membres', style: VxText.title(layout.pageTitleSize)),
        SizedBox(height: layout.space(VxSpace.xs)),
        Text(
          'Leurs avis, leurs listes et ce qu’ils regardent arriveront dans votre fil.',
          style: VxText.body(layout.bodySize, color: VxColors.textSecondary),
        ),
        SizedBox(height: layout.sectionGap),
        if (value == null)
          NetworkLoading(error: suggestions.error, onRetry: () => ref.invalidate(suggestionsProvider))
        else if (value.isEmpty)
          Text(
            'Aucun compte à suggérer pour l’instant : cherchez des membres dans la recherche.',
            style: VxText.body(layout.bodySize, color: VxColors.textMuted),
          )
        else
          Wrap(
            spacing: layout.cardGap,
            runSpacing: layout.cardGap,
            children: [
              for (final suggestion in value)
                SizedBox(height: SuggestionCard.heightOf(layout), child: SuggestionCard(suggestion: suggestion)),
            ],
          ),
        SizedBox(height: pageBottomPadding(context) - MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}
