import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/features.dart';
import 'core/theme.dart';
import 'core/widgets/app_loading.dart';
import 'core/widgets/common.dart';
import 'features/account/account_screen.dart';
import 'features/account/devices_screen.dart';
import 'features/auth/device_login.dart';
import 'features/auth/login_screen.dart';
import 'features/catalog/artwork.dart';
import 'features/catalog/artwork_screen.dart';
import 'features/auth/session.dart';
import 'features/catalog/details_screen.dart';
import 'features/catalog/description_screen.dart';
import 'features/catalog/home_screen.dart';
import 'features/catalog/weekly_releases_screen.dart';
import 'features/catalog/list_screen.dart';
import 'features/catalog/models.dart';
import 'features/catalog/person_screen.dart';
import 'features/library/my_list_screen.dart';
import 'features/notifications/inbox.dart';
import 'features/notifications/inbox_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/messages/conversation_screen.dart';
import 'features/messages/conversations_screen.dart';
import 'features/messages/group_screen.dart';
import 'features/messages/messages.dart' show newGroupLocation;
import 'features/network/feed_screen.dart';
import 'features/network/hidden_accounts_screen.dart';
import 'features/network/list_screen.dart';
import 'features/network/onboarding_screen.dart';
import 'features/network/profile_pages.dart';
import 'features/network/profile_sections.dart' show WatchlistCard;
import 'features/network/review_screen.dart';
import 'features/playback/player_screen.dart';
import 'features/profiles/profile_editor_screen.dart';
import 'features/profiles/profile_preferences_screen.dart';
import 'features/profiles/profile_settings_screen.dart';
import 'features/profiles/row_preferences.dart';
import 'features/profiles/rows_settings_screen.dart';
import 'features/search/search_screen.dart';
import 'features/social/profile_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/back_navigation_guard.dart';
import 'features/tv/channel_screen.dart';
import 'features/tv/tv_channels_screen.dart';
import 'features/tv/models.dart';
import 'features/tmdb/review_screen.dart';
import 'features/tmdb/reviews_screen.dart';

/// Every in-app route requires an authenticated account; profile-specific routes also require an active profile.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  // Only what the redirects depend on: editing the profile (avatar…) must not rebuild the pages.
  ref.listen(sessionProvider.select((s) => (s.status, s.profile == null)), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  // Deep link opened before session restoration, or a protected page requested before sign-in.
  String? pending;

  // A main page (tab of the navigation) is a MaterialPage, like every other page: it changes with
  // the theme's transition (vxPageTransition), and the page it replaces fades out with it (a
  // MaterialPageRoute only animates its exit under another MaterialPageRoute).
  Page<void> tab(GoRouterState state, Widget child) => MaterialPage<void>(key: state.pageKey, child: child);
  Widget guarded(String location, Widget child) => BackNavigationGuard(location: location, child: child);
  // Live TV is hidden for now (core/features.dart): its pages lead to the home page.
  String? liveTvOnly(BuildContext context, GoRouterState state) => ref.read(liveTvProvider) ? null : '/accueil';
  // The social network: not for a child's profile.
  String? socialOnly(BuildContext context, GoRouterState state) =>
      socialAvailable(ref.read(sessionProvider)) ? null : '/accueil';
  int? idOf(GoRouterState state) => int.tryParse(state.pathParameters['id'] ?? '');

  return GoRouter(
    initialLocation: '/accueil',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      // A profile's link (vixeo.app/pseudo, « Partager »), opened by Android in the app: a path
      // no page of the app has (the last route, profileLinkPath).
      final member = memberOfLink(state.uri.path, unknownPage: state.fullPath == profileLinkPath);
      if (member != null) {
        final mine = member.toLowerCase() == session.profile?.username?.toLowerCase();
        return mine ? '/profil' : '/membre/${Uri.encodeComponent(member)}';
      }
      final location = state.matchedLocation;
      const authPages = {'/connexion', EmailLoginScreen.location, '/inscription'};
      if (session.status == SessionStatus.restoring || session.status == SessionStatus.unreachable) {
        if (location != '/demarrage') {
          if (!authPages.contains(location)) pending = state.uri.toString();
          return '/demarrage';
        }
        return null;
      }
      if (session.status == SessionStatus.signedOut) {
        if (authPages.contains(location)) return null;
        if (location != '/demarrage') pending = state.uri.toString();
        final target = pending;
        return target == null
            ? '/connexion'
            : '/connexion?redirect=${Uri.encodeComponent(target)}';
      }
      // Approving a TV code needs an account, not a profile.
      if (location == '/tv') return null;
      if (pending != null && pending!.startsWith('/tv')) {
        final target = pending;
        pending = null;
        return target;
      }
      if (session.profile == null) {
        // Single-profile accounts go straight into the app; the API resolves the account profile.
        return location == '/accueil' ? null : '/accueil';
      }
      if (!session.profile.registrationCompleted) {
        final setupPath = '/profils/modifier/${session.profile.id}';
        if (location != setupPath || state.uri.queryParameters['inscription'] != '1') {
          return '$setupPath?inscription=1';
        }
        return null;
      }
      if (state.uri.queryParameters['inscription'] == '1' && location.startsWith('/profils/modifier/')) {
        return OnboardingScreen.needed(session) ? OnboardingScreen.location : '/accueil';
      }
      if (authPages.contains(location) || location == '/profils' || location == '/demarrage') {
        // Finish authentication and continue to onboarding or the requested destination.
        final target = pending ?? (OnboardingScreen.needed(session) ? OnboardingScreen.location : '/accueil');
        pending = null;
        return target;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/demarrage', builder: (_, state) => guarded(state.uri.path, const SplashScreen())),
      // The welcome page (« Continuer avec Google / Apple / l’e-mail »), then the e-mail form.
      GoRoute(path: '/connexion', builder: (_, state) => guarded(state.uri.path, const LoginScreen())),
      GoRoute(
        path: EmailLoginScreen.location,
        builder: (_, state) => guarded(state.uri.path, const EmailLoginScreen()),
      ),
      GoRoute(path: '/inscription', redirect: (_, _) => EmailLoginScreen.location),
      GoRoute(path: '/profils', redirect: (_, _) => '/accueil'),
      GoRoute(
        path: '/profils/modifier/:id',
        builder: (_, state) => ProfileEditorScreen(
          profileId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          onboarding: state.uri.queryParameters['inscription'] == '1',
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/accueil', pageBuilder: (_, state) => tab(state, const HomeScreen())),
          GoRoute(path: '/sorties', pageBuilder: (_, state) => tab(state, const WeeklyReleasesScreen())),
          // The "Films" and "Séries" pages were removed: their former addresses lead to the home page.
          GoRoute(
            path: '/chaines-tv',
            redirect: liveTvOnly,
            pageBuilder: (_, state) => tab(state, const TvChannelsScreen()),
          ),
          // Every channel of a category: the round arrow of a row of the « Chaînes TV » page.
          GoRoute(
            path: '/chaines-tv/categorie/:id',
            redirect: liveTvOnly,
            builder: (_, state) => TvCategoryScreen(
              categoryId: state.pathParameters['id'] ?? '',
              title: state.uri.queryParameters['titre'],
            ),
          ),
          GoRoute(
            path: '/recherche',
            pageBuilder: (_, state) => tab(state, SearchScreen(initialType: state.extra as MediaType?)),
          ),
          // "Mes avis": the profile's ratings and comments (vixeo_backend/docs/avis.md).
          GoRoute(path: '/avis', pageBuilder: (_, state) => tab(state, const ReviewsScreen())),
          // A review as a publication, with its comments (vixeo_backend/docs/social.md).
          GoRoute(
            path: '/avis/:id',
            redirect: (context, state) => socialOnly(context, state) ?? (idOf(state) == null ? '/avis' : null),
            builder: (_, state) => ReviewThreadScreen(id: idOf(state)!),
          ),
          // "Mon avis": one review, to change or remove (/avis/tv/1399?saison=1&episode=2 for an episode).
          GoRoute(
            path: '/avis/:type/:id',
            builder: (_, state) =>
                ReviewScreen(
                  target: ReviewScreen.targetOf(state.pathParameters, state.uri.queryParameters),
                  // What the caller already knows (title, rating): never in the address.
                  subject: state.extra is RatingSubject ? state.extra! as RatingSubject : null,
                ),
          ),
          // « Notifications »: follow requests, next episodes, what other members did (not for a
          // child's profile). Opened from the bell of the profile page (not in the navigation).
          GoRoute(
            path: InboxScreen.location,
            redirect: (_, _) => socialAvailable(ref.read(sessionProvider)) ? null : '/accueil',
            builder: (_, _) => const InboxScreen(),
          ),
          // « Fil d'actualité »: what the members did (phones, tablets, computers).
          GoRoute(
            path: FeedScreen.location,
            redirect: socialOnly,
            pageBuilder: (_, state) => tab(state, const FeedScreen()),
          ),
          // « À voir » (« Ma liste » until 23/11/2026, first of the lists; every profile has it, a
          // child's too), then the other lists. « a-voir » and « nouvelle » before « :id ».
          GoRoute(path: WatchlistCard.location, builder: (_, _) => const MyListScreen()),
          GoRoute(
            path: ListEditorScreen.newLocation,
            redirect: socialOnly,
            builder: (_, state) => ListEditorScreen(
              title: state.uri.queryParameters['titre'],
              item: state.uri.queryParameters['item'],
            ),
          ),
          GoRoute(
            path: '/listes/:id',
            redirect: (context, state) => socialOnly(context, state) ?? (idOf(state) == null ? '/accueil' : null),
            builder: (_, state) => ListDetailsScreen(id: idOf(state)!),
          ),
          GoRoute(
            path: '/listes/:id/modifier',
            redirect: (context, state) => socialOnly(context, state) ?? (idOf(state) == null ? '/accueil' : null),
            builder: (_, state) => ListEditorScreen(id: idOf(state)!),
          ),
          GoRoute(path: HiddenAccountsScreen.location, redirect: socialOnly, builder: (_, _) => const HiddenAccountsScreen()),
          // My lists and my year (the « Listes » and « Vus » tabs of my page).
          GoRoute(path: '/profil/listes', redirect: socialOnly, builder: (_, _) => const ProfileListsScreen()),
          GoRoute(
            path: '/profil/bilan',
            redirect: socialOnly,
            builder: (_, state) => YearStatsScreen(year: int.tryParse(state.uri.queryParameters['annee'] ?? '')),
          ),
          GoRoute(path: '/profil', pageBuilder: (_, state) => tab(state, const ProfileScreen())),
          // « Messages » (vixeo_backend/docs/messagerie.md): not for a child's profile.
          GoRoute(
            path: ConversationsScreen.location,
            redirect: (_, _) => socialAvailable(ref.read(sessionProvider)) ? null : '/accueil',
            pageBuilder: (_, state) => tab(state, const ConversationsScreen()),
          ),
          // Before /messages/:id, which would take « nouveau-groupe » for an id.
          GoRoute(
            path: newGroupLocation,
            redirect: (_, _) => socialAvailable(ref.read(sessionProvider)) ? null : '/accueil',
            builder: (_, _) => const NewGroupScreen(),
          ),
          GoRoute(
            path: '/messages/:id',
            redirect: (_, state) => !socialAvailable(ref.read(sessionProvider))
                ? '/accueil'
                : int.tryParse(state.pathParameters['id'] ?? '') == null
                ? ConversationsScreen.location
                : null,
            builder: (_, state) => ConversationScreen(id: int.parse(state.pathParameters['id']!)),
          ),
          GoRoute(
            path: '/messages/:id/groupe',
            redirect: (_, state) => !socialAvailable(ref.read(sessionProvider))
                ? '/accueil'
                : int.tryParse(state.pathParameters['id'] ?? '') == null
                ? ConversationsScreen.location
                : null,
            builder: (_, state) => GroupSettingsScreen(id: int.parse(state.pathParameters['id']!)),
          ),
          GoRoute(path: '/parametres', pageBuilder: (_, state) => tab(state, const ProfileSettingsScreen())),
          GoRoute(path: '/membre/:username', builder: (_, state) => PublicProfileScreen(username: state.pathParameters['username'] ?? '')),
          GoRoute(
            path: '/membre/:username/listes',
            redirect: socialOnly,
            builder: (_, state) => ProfileListsScreen(username: state.pathParameters['username']),
          ),
          GoRoute(
            path: '/membre/:username/bilan',
            redirect: socialOnly,
            builder: (_, state) => YearStatsScreen(
              username: state.pathParameters['username'],
              year: int.tryParse(state.uri.queryParameters['annee'] ?? ''),
            ),
          ),
          GoRoute(path: '/membre/:username/:section', builder: (_, state) => SocialCollectionScreen(
            username: state.pathParameters['username'], section: state.pathParameters['section'] ?? '',
          )),
          GoRoute(path: '/profil/social/:section', builder: (_, state) => SocialCollectionScreen(
            section: state.pathParameters['section'] ?? '',
          )),
          GoRoute(
            path: ProfilePreferencesScreen.location,
            builder: (_, state) => ProfilePreferencesScreen(setting: state.uri.queryParameters['reglage']),
          ),
          // Order and visibility of the rows of the home page and of the « Chaînes TV » page.
          GoRoute(
            path: RowsSettingsScreen.homeLocation,
            builder: (_, _) => const RowsSettingsScreen(page: RowsPage.home),
          ),
          GoRoute(
            path: RowsSettingsScreen.channelsLocation,
            redirect: liveTvOnly,
            builder: (_, _) => const RowsSettingsScreen(page: RowsPage.channels),
          ),
          GoRoute(path: '/profil/compte', builder: (_, _) => const AccountScreen()),
          GoRoute(path: '/profil/appareils', builder: (_, _) => const DevicesScreen()),
          GoRoute(path: NotificationsScreen.location, builder: (_, _) => const NotificationsScreen()),
          GoRoute(
            path: '/personne/:id',
            builder: (_, state) => PersonScreen(id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
          ),
          // « Voir tout » of a person page: every title, most voted or newest first.
          GoRoute(
            path: '/personne/:id/connu-pour',
            builder: (_, state) => PersonTitlesScreen(
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
              sort: PersonCreditsSort.popular,
            ),
          ),
          GoRoute(
            path: '/personne/:id/filmographie',
            builder: (_, state) => PersonTitlesScreen(
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
              sort: PersonCreditsSort.date,
            ),
          ),
          // « Connecter une TV » (from « Paramètres »); ?code= prefills the code.
          GoRoute(
            path: '/tv',
            builder: (_, state) =>
                guarded(state.uri.path, DeviceApproveScreen(initialCode: state.uri.queryParameters['code'])),
          ),
          // A live channel's page (like a title page): its programme guide and « Regarder ».
          GoRoute(
            path: '/chaine/:id',
            redirect: liveTvOnly,
            builder: (_, state) => ChannelScreen(
              id: state.pathParameters['id'] ?? '',
              initial: state.extra is TvChannel ? state.extra as TvChannel : null,
            ),
          ),
          // "Voir tout" of a home row: /liste/movie/trending?titre=Films%20du%20moment.
          GoRoute(
            path: '/liste/:type/:list',
            builder: (_, state) => TitleListScreen(
              type: MediaType.parse(state.pathParameters['type']),
              list: state.pathParameters['list'] ?? '',
              title: state.uri.queryParameters['titre'],
            ),
          ),
          // The whole summary or biography (« Lire la suite »): its text comes with the route.
          GoRoute(
            path: DescriptionScreen.location,
            redirect: (_, state) => DescriptionScreen.fromExtra(state.extra) == null ? '/accueil' : null,
            builder: (_, state) => DescriptionScreen.fromExtra(state.extra)!,
          ),
          GoRoute(
            path: '/titre/:type/:id',
            builder: (_, state) => DetailsScreen(
              type: MediaType.parse(state.pathParameters['type']),
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            ),
          ),
          // « Voir tout » of a title page: every recommendation, everyone of the credits.
          GoRoute(
            path: '/titre/:type/:id/recommandations',
            builder: (_, state) => RecommendationsScreen(
              type: MediaType.parse(state.pathParameters['type']),
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            ),
          ),
          // « Avis populaires » of a title page: every review of the title.
          GoRoute(
            path: '/titre/:type/:id/avis',
            redirect: (context, state) =>
                socialOnly(context, state) == null ? null : '/titre/${state.pathParameters['type']}/${state.pathParameters['id']}',
            builder: (_, state) => TitleReviewsScreen(
              type: MediaType.parse(state.pathParameters['type']),
              id: idOf(state) ?? 0,
              title: state.uri.queryParameters['titre'],
            ),
          ),
          // « Affiches, arrière-plans, logos » of a title: a profile's choice.
          GoRoute(
            path: '/titre/:type/:id/images',
            redirect: (_, state) => ref.read(sessionProvider).profile == null
                ? '/titre/${state.pathParameters['type']}/${state.pathParameters['id']}'
                : null,
            builder: (_, state) => ArtworkScreen(
              type: MediaType.parse(state.pathParameters['type']),
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
              initialKind: ArtworkKind.fromSlug(state.uri.queryParameters['sorte']),
            ),
          ),
          // « Voir tout » of « Distribution » and « Équipe technique ».
          GoRoute(
            path: '/titre/:type/:id/distribution',
            builder: (_, state) => CreditsScreen(
              type: MediaType.parse(state.pathParameters['type']),
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            ),
          ),
          GoRoute(
            path: '/titre/:type/:id/equipe',
            builder: (_, state) => CreditsScreen(
              type: MediaType.parse(state.pathParameters['type']),
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
              crew: true,
            ),
          ),
        ],
      ),
      // The first launch of a profile with social features (no navigation).
      GoRoute(
        path: OnboardingScreen.location,
        redirect: (_, _) => socialAvailable(ref.read(sessionProvider)) ? null : '/accueil',
        builder: (_, state) => guarded(state.uri.path, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/lecture/:type/:id',
        builder: (_, state) => guarded(
          state.uri.path,
          PlayerScreen(
            type: MediaType.parse(state.pathParameters['type']),
            id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
            season: int.tryParse(state.uri.queryParameters['saison'] ?? ''),
            episode: int.tryParse(state.uri.queryParameters['episode'] ?? ''),
          ),
        ),
      ),
      // Last: vixeo.app/pseudo (like Twitter), see profileLinkRoute.
      profileLinkRoute(),
    ],
    errorBuilder: (context, state) => guarded(
      state.uri.path,
      const Scaffold(
        body: EmptyState(icon: Icons.explore_off_outlined, title: 'Page introuvable'),
      ),
    ),
  );
});

/// Shown while the saved session is checked (the start-up loading, [AppLoading]), or when the
/// API cannot be reached.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session.status != SessionStatus.unreachable) return const Scaffold(body: AppLoading());
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VxLogo(size: 40),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                session.message ?? 'Impossible de joindre le serveur.',
                textAlign: TextAlign.center,
                style: VxText.body(16, color: VxColors.textSoft),
              ),
            ),
            const SizedBox(height: 20),
            VxButton(
              label: 'Réessayer',
              autofocus: true,
              onPressed: () => ref.read(sessionProvider.notifier).restore(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Path of the last route of the app: one word that no page of the app is, `/lea`.
const profileLinkPath = '/:username';

/// The last route of the app: a profile's link without @ (vixeo.app/lea, like Twitter,
/// developer's request, 21/11/2026), opened by Android in the app. The top-level redirect sends a
/// username to the profile ([memberOfLink]); anything else that lands here goes home. Usernames are
/// never a page of the app (the API reserves them: vixeo_backend `Usernames::RESERVED`).
GoRoute profileLinkRoute() => GoRoute(path: profileLinkPath, redirect: (_, _) => '/accueil');

/// The username of a profile's link, `/lea`, when [unknownPage] (the path matched
/// [profileLinkRoute], no page of the app); null for any other path.
String? memberOfLink(String path, {bool unknownPage = false}) {
  if (!unknownPage) return null;
  final username = Uri.decodeComponent(path).substring(1);
  return RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch(username) ? username : null;
}
