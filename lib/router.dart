import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/features.dart';
import 'core/theme.dart';
import 'core/widgets/app_loading.dart';
import 'core/widgets/common.dart';
import 'features/account/account_screen.dart';
import 'features/account/devices_screen.dart';
import 'features/addons/addons_screen.dart';
import 'features/auth/device_login.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/password_reset_screen.dart';
import 'features/auth/register_screen.dart' show RegisterScreen;
import 'features/auth/session.dart';
import 'features/catalog/details_screen.dart';
import 'features/catalog/home_screen.dart';
import 'features/catalog/list_screen.dart';
import 'features/catalog/models.dart';
import 'features/catalog/person_screen.dart';
import 'features/library/my_list_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/playback/player_screen.dart';
import 'features/profiles/advanced_settings_screen.dart';
import 'features/profiles/profile_editor_screen.dart';
import 'features/profiles/profile_preferences_screen.dart';
import 'features/profiles/profile_settings_screen.dart';
import 'features/profiles/profiles_screen.dart';
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

/// Public catalog and playback routes are available to guests. Personal features require an account and profile.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  // Only what the redirects depend on: editing the profile (avatar…) must not rebuild the pages.
  ref.listen(sessionProvider.select((s) => (s.status, s.profile == null)), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  // Deep link opened before session restoration, or a protected page requested by a guest.
  String? pending;

  // A main page (tab of the navigation) is a MaterialPage, like every other page: it changes with
  // the theme's transition (vxPageTransition), and the page it replaces fades out with it (a
  // MaterialPageRoute only animates its exit under another MaterialPageRoute).
  Page<void> tab(GoRouterState state, Widget child) => MaterialPage<void>(key: state.pageKey, child: child);
  Widget guarded(String location, Widget child) => BackNavigationGuard(location: location, child: child);
  // Live TV is hidden for now (core/features.dart): its pages lead to the home page.
  String? liveTvOnly(BuildContext context, GoRouterState state) => ref.read(liveTvProvider) ? null : '/accueil';

  return GoRouter(
    initialLocation: '/accueil',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      // A profile's link (www.vixeo.app/pseudo, « Partager »; old /@pseudo), opened by Android in
      // the app: a path no page of the app has (the last route, profileLinkPath).
      final member = memberOfLink(state.uri.path, unknownPage: state.fullPath == profileLinkPath);
      if (member != null) {
        final mine = member.toLowerCase() == session.profile?.username?.toLowerCase();
        return mine ? '/profil' : '/membre/${Uri.encodeComponent(member)}';
      }
      final location = state.matchedLocation;
      const authPages = {'/connexion', '/inscription', '/mot-de-passe-oublie'};
      const guestAllowed = {
        '/accueil', '/films', '/series', '/liste', '/recherche', '/chaines-tv', '/personne', '/titre', '/chaine', '/lecture', '/tv-live', '/membre',
      };
      const accountOnly = {
        '/profils', '/profils/gestion', '/ma-liste', '/avis', '/profil', '/parametres', '/profil/social/edition', '/profil/social/avis', '/profil/social/liste', '/profil/social/abonnements', '/profil/social/abonnes', '/profil/avatar', '/profil/controle-parental',
        '/profil/code-pin', '/profil/parametres', '/profil/compte', '/profil/appareils',
        '/profil/connexions', '/profil/tmdb', '/profil/notes', '/profil/notifications', '/profil/avance', '/profil/plugins', '/tv',
      };
      if (session.status == SessionStatus.restoring || session.status == SessionStatus.unreachable) {
        if (location != '/demarrage') {
          if (!authPages.contains(location)) pending = state.uri.toString();
          return '/demarrage';
        }
        return null;
      }
      if (session.status == SessionStatus.signedOut) {
        if (authPages.contains(location)) return null;
        return '/connexion';
      }
      if (session.isGuest) {
        if (location == '/accueil' && state.uri.queryParameters['mode'] == 'invite') {
          pending = null;
          return '/accueil';
        }
        if (location == '/demarrage') {
          final target = pending;
          pending = null;
          if (target != null) {
            final targetPath = Uri.parse(target).path;
            if (guestAllowed.any((path) => targetPath == path || targetPath.startsWith('$path/'))) {
              return target;
            }
            if (accountOnly.any((path) => targetPath == path || targetPath.startsWith('$path/'))) {
              pending = target;
              return '/connexion?redirect=${Uri.encodeComponent(target)}';
            }
          }
          return '/accueil';
        }
        if (authPages.contains(location)) {
          pending = state.uri.queryParameters['redirect'] ?? pending;
          return null;
        }
        final isPublic = guestAllowed.any((path) => location == path || location.startsWith('$path/'));
        if (isPublic) return null;
        if (accountOnly.any((path) => location == path || location.startsWith('$path/'))) {
          pending = state.uri.toString();
        }
        return '/connexion';
      }
      // Approving a TV code needs an account, not a profile.
      if (location == '/tv') return null;
      if (pending != null && pending!.startsWith('/tv')) {
        final target = pending;
        pending = null;
        return target;
      }
      if (session.profile == null) {
        // « Qui regarde ? » and its « Ajouter / Modifier un profil » pages.
        final picker = location == '/profils' || (location.startsWith('/profils/') && location != '/profils/gestion');
        return picker ? null : '/profils';
      }
      if (authPages.contains(location) || location == '/profils' || location == '/demarrage') {
        final target = pending ?? '/accueil';
        pending = null;
        return target;
      }
      return null;
    },
    routes: [
      // A profile's link (www.vixeo.app/@pseudo): the redirect above opens the profile.
      GoRoute(path: '/@:username', redirect: (_, state) => '/membre/${state.pathParameters['username']}'),
      GoRoute(path: '/demarrage', builder: (_, state) => guarded(state.uri.path, const SplashScreen())),
      GoRoute(path: '/connexion', builder: (_, state) => guarded(state.uri.path, const LoginScreen())),
      GoRoute(path: '/inscription', builder: (_, state) => guarded(state.uri.path, const RegisterScreen())),
      GoRoute(
        path: '/mot-de-passe-oublie',
        builder: (_, state) => guarded(state.uri.path, PasswordResetScreen(initialEmail: state.extra as String?)),
      ),
      GoRoute(path: '/profils', builder: (_, state) => guarded(state.uri.path, const ProfilesScreen())),
      // « Gérer les profils » (« Qui regarde ? »): add and change a profile, without the navigation.
      GoRoute(path: ProfileEditorScreen.newLocation, builder: (_, _) => const ProfileEditorScreen()),
      GoRoute(
        path: '/profils/modifier/:id',
        builder: (_, state) => ProfileEditorScreen(profileId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/accueil', pageBuilder: (_, state) => tab(state, const HomeScreen())),
          // The "Films" and "Séries" pages were removed: their former addresses lead to the home page.
          GoRoute(path: '/films', redirect: (_, _) => '/accueil'),
          GoRoute(path: '/series', redirect: (_, _) => '/accueil'),
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
          GoRoute(path: '/tv-live', redirect: (_, _) => '/chaines-tv'),
          GoRoute(
            path: '/recherche',
            pageBuilder: (_, state) => tab(state, SearchScreen(initialType: state.extra as MediaType?)),
          ),
          GoRoute(path: '/ma-liste', pageBuilder: (_, state) => tab(state, const MyListScreen())),
          // "Mes avis": the profile's ratings and comments (vixeo_backend/docs/avis.md).
          GoRoute(path: '/avis', pageBuilder: (_, state) => tab(state, const ReviewsScreen())),
          // "Mon avis": one review, to change or remove (/avis/tv/1399?saison=1&episode=2 for an episode).
          GoRoute(
            path: '/avis/:type/:id',
            builder: (_, state) =>
                ReviewScreen(target: ReviewScreen.targetOf(state.pathParameters, state.uri.queryParameters)),
          ),
          GoRoute(path: '/profil', pageBuilder: (_, state) => tab(state, const ProfileScreen())),
          // Former page: managing is on « Qui regarde ? » now.
          GoRoute(path: '/profils/gestion', redirect: (_, _) => '/profils'),
          GoRoute(path: '/parametres', pageBuilder: (_, state) => tab(state, const ProfileSettingsScreen())),
          GoRoute(path: '/profil/social/edition', builder: (_, _) => const SocialProfileEditScreen()),
          GoRoute(path: '/membre/:username', builder: (_, state) => PublicProfileScreen(username: state.pathParameters['username'] ?? '')),
          GoRoute(path: '/membre/:username/:section', builder: (_, state) => SocialCollectionScreen(
            username: state.pathParameters['username'], section: state.pathParameters['section'] ?? 'list',
          )),
          GoRoute(path: '/profil/social/:section', builder: (_, state) => SocialCollectionScreen(
            section: state.pathParameters['section'] ?? 'list',
          )),
          // Former pages (developer's request): the avatar is changed in « Modifier le profil »
          // (« Qui regarde ? » → « Gérer les profils »), the parental PIN on « Contrôle parental ».
          GoRoute(path: '/profil/avatar', redirect: (_, _) => '/parametres'),
          // Former pages (developer's request): the restrictions are in « Modifier le profil »
          // (« Qui regarde ? » → « Gérer les profils »), the parental PIN in « Mon compte ».
          GoRoute(path: '/profil/controle-parental', redirect: (_, _) => '/profil/compte'),
          GoRoute(path: '/profil/code-pin', redirect: (_, _) => '/profil/compte'),
          GoRoute(path: '/profil/parametres', builder: (_, _) => const ProfilePreferencesScreen()),
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
          // No more « Connexions » page: a TMDb account is no longer linked (developer's request).
          GoRoute(path: '/profil/connexions', redirect: (_, _) => '/parametres'),
          GoRoute(path: NotificationsScreen.location, builder: (_, _) => const NotificationsScreen()),
          GoRoute(path: AdvancedSettingsScreen.location, builder: (_, _) => const AdvancedSettingsScreen()),
          // Plug-ins in the Stremio add-on format (vixeo_backend/docs/plugins.md).
          GoRoute(path: AddonsScreen.location, builder: (_, _) => const AddonsScreen()),
          GoRoute(path: '/profil/tmdb', redirect: (_, _) => '/parametres'),
          GoRoute(path: '/profil/notes', redirect: (_, _) => '/avis'),
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
          GoRoute(
            path: '/titre/:type/:id/distribution',
            builder: (_, state) => CreditsScreen(
              type: MediaType.parse(state.pathParameters['type']),
              id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
              title: state.uri.queryParameters['titre'],
            ),
          ),
        ],
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
      // Last: www.vixeo.app/pseudo (like Twitter), see profileLinkRoute.
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

/// The last route of the app: a profile's link without @ (www.vixeo.app/lea, like Twitter,
/// developer's request, 21/11/2026), opened by Android in the app. The top-level redirect sends a
/// username to the profile ([memberOfLink]); anything else that lands here goes home. Usernames are
/// never a page of the app (the API reserves them: vixeo_backend `Usernames::RESERVED`).
GoRoute profileLinkRoute() => GoRoute(path: profileLinkPath, redirect: (_, _) => '/accueil');

/// The username of a profile's link: `/lea` when [unknownPage] (the path matched
/// [profileLinkRoute], no page of the app), or the old `/@lea`; null for any other path.
String? memberOfLink(String path, {bool unknownPage = false}) {
  final decoded = Uri.decodeComponent(path);
  final String username;
  if (decoded.startsWith('/@')) {
    username = decoded.substring(2).split('/').first;
  } else if (unknownPage) {
    username = decoded.substring(1);
  } else {
    return null;
  }
  return RegExp(r'^[A-Za-z0-9_]{3,30}$').hasMatch(username) ? username : null;
}
