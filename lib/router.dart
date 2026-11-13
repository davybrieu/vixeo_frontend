import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/widgets/app_loading.dart';
import 'core/widgets/common.dart';
import 'features/account/account_screen.dart';
import 'features/account/devices_screen.dart';
import 'features/auth/device_login.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/password_reset_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/session.dart';
import 'features/catalog/details_screen.dart';
import 'features/catalog/home_screen.dart';
import 'features/catalog/list_screen.dart';
import 'features/catalog/models.dart';
import 'features/catalog/person_screen.dart';
import 'features/library/my_list_screen.dart';
import 'features/playback/player_screen.dart';
import 'features/profiles/parental_control_screen.dart';
import 'features/profiles/parental_pin.dart';
import 'features/profiles/profile_preferences_screen.dart';
import 'features/profiles/profile_settings_screen.dart';
import 'features/profiles/profiles_screen.dart';
import 'features/search/search_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/back_navigation_guard.dart';
import 'features/tv/channel_screen.dart';
import 'features/tv/tv_channels_screen.dart';
import 'features/tv/models.dart';
import 'features/tmdb/connections_screen.dart';
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

  // A main page (tab of the navigation) fades in like every other page.
  Page<void> tab(GoRouterState state, Widget child) => CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: vxPageFade,
    reverseTransitionDuration: vxPageFade,
    transitionsBuilder: (_, animation, _, child) => vxFadeTransition(animation, child),
  );
  Widget guarded(String location, Widget child) => BackNavigationGuard(location: location, child: child);

  return GoRouter(
    initialLocation: '/accueil',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;
      const authPages = {'/connexion', '/inscription', '/mot-de-passe-oublie'};
      const guestAllowed = {
        '/accueil', '/films', '/series', '/liste', '/recherche', '/chaines-tv', '/personne', '/titre', '/chaine', '/lecture', '/tv-live',
      };
      const accountOnly = {
        '/profils', '/ma-liste', '/avis', '/profil', '/profil/avatar', '/profil/controle-parental',
        '/profil/code-pin', '/profil/parametres', '/profil/compte', '/profil/appareils',
        '/profil/connexions', '/profil/tmdb', '/profil/notes', '/tv',
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
        return location == '/profils' ? null : '/profils';
      }
      if (authPages.contains(location) || location == '/profils' || location == '/demarrage') {
        final target = pending ?? '/accueil';
        pending = null;
        return target;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/demarrage', builder: (_, state) => guarded(state.uri.path, const SplashScreen())),
      GoRoute(path: '/connexion', builder: (_, state) => guarded(state.uri.path, const LoginScreen())),
      GoRoute(path: '/inscription', builder: (_, state) => guarded(state.uri.path, const RegisterScreen())),
      GoRoute(
        path: '/mot-de-passe-oublie',
        builder: (_, state) => guarded(state.uri.path, PasswordResetScreen(initialEmail: state.extra as String?)),
      ),
      GoRoute(path: '/profils', builder: (_, state) => guarded(state.uri.path, const ProfilesScreen())),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/accueil', pageBuilder: (_, state) => tab(state, const HomeScreen())),
          // The "Films" and "Séries" pages were removed: their former addresses lead to the home page.
          GoRoute(path: '/films', redirect: (_, _) => '/accueil'),
          GoRoute(path: '/series', redirect: (_, _) => '/accueil'),
          GoRoute(path: '/chaines-tv', pageBuilder: (_, state) => tab(state, const TvChannelsScreen())),
          GoRoute(path: '/tv-live', redirect: (_, _) => '/chaines-tv'),
          GoRoute(
            path: '/recherche',
            pageBuilder: (_, state) => tab(state, SearchScreen(initialType: state.extra as MediaType?)),
          ),
          GoRoute(path: '/ma-liste', pageBuilder: (_, state) => tab(state, const MyListScreen())),
          // "Mes avis": ratings of the TMDb account and comments (vixeo_backend/docs/compte-tmdb.md).
          GoRoute(path: '/avis', pageBuilder: (_, state) => tab(state, const ReviewsScreen())),
          // "Mon avis": one review, to change or remove (/avis/tv/1399?saison=1&episode=2 for an episode).
          GoRoute(
            path: '/avis/:type/:id',
            builder: (_, state) =>
                ReviewScreen(target: ReviewScreen.targetOf(state.pathParameters, state.uri.queryParameters)),
          ),
          GoRoute(path: '/profil', pageBuilder: (_, state) => tab(state, const ProfileSettingsScreen())),
          GoRoute(path: '/profil/avatar', builder: (_, _) => const AvatarPickerScreen()),
          GoRoute(path: '/profil/controle-parental', builder: (_, _) => const ParentalControlScreen()),
          GoRoute(path: '/profil/code-pin', builder: (_, _) => const ParentalPinScreen()),
          GoRoute(path: '/profil/parametres', builder: (_, _) => const ProfilePreferencesScreen()),
          GoRoute(path: '/profil/compte', builder: (_, _) => const AccountScreen()),
          GoRoute(path: '/profil/appareils', builder: (_, _) => const DevicesScreen()),
          // Services linked to the profile (TMDb). The former addresses lead to the new pages.
          GoRoute(path: '/profil/connexions', builder: (_, _) => const ConnectionsScreen()),
          GoRoute(path: '/profil/tmdb', redirect: (_, _) => '/profil/connexions'),
          GoRoute(path: '/profil/notes', redirect: (_, _) => '/avis'),
          GoRoute(
            path: '/personne/:id',
            builder: (_, state) => PersonScreen(id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
          ),
          // Opened by the QR code of a TV: /tv?code=K7F29Q.
          GoRoute(
            path: '/tv',
            builder: (_, state) =>
                guarded(state.uri.path, DeviceApproveScreen(initialCode: state.uri.queryParameters['code'])),
          ),
          // A live channel's page (like a title page): its programme guide and « Regarder ».
          GoRoute(
            path: '/chaine/:id',
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
