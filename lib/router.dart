import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/widgets/common.dart';
import 'features/account/about_screen.dart';
import 'features/account/account_screen.dart';
import 'features/account/devices_screen.dart';
import 'features/account/privacy_screen.dart';
import 'features/auth/device_login.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/password_reset_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/session.dart';
import 'features/catalog/details_screen.dart';
import 'features/catalog/home_screen.dart';
import 'features/catalog/models.dart';
import 'features/catalog/person_screen.dart';
import 'features/library/my_list_screen.dart';
import 'features/playback/player_screen.dart';
import 'features/profiles/parental_control_screen.dart';
import 'features/profiles/playback_settings_screen.dart';
import 'features/profiles/profile_settings_screen.dart';
import 'features/profiles/profiles_screen.dart';
import 'features/search/search_screen.dart';
import 'features/shell/app_shell.dart';

/// Navigator of the router, for dialogs opened from above it (update suggestion).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Routes. Sign-in is the entry page: every route redirects there while signed out,
/// then to "Qui regarde ?" until a profile is chosen.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  // Only what the redirects depend on: editing the profile (avatar…) must not rebuild the pages.
  ref.listen(sessionProvider.select((s) => (s.status, s.profile == null)), (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  // Deep link opened before the session was restored, or while signed out (QR code of a TV).
  String? pending;

  Page<void> tab(Widget child) => NoTransitionPage(child: child);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/connexion',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;
      const authPages = {'/connexion', '/inscription', '/mot-de-passe-oublie'};
      // Readable by everyone, at any time (the privacy policy is also the link given to Apple).
      const publicPages = {'/confidentialite', '/a-propos'};
      if (publicPages.contains(location)) return null;

      if (session.status == SessionStatus.restoring || session.status == SessionStatus.unreachable) {
        if (location != '/demarrage') {
          if (!authPages.contains(location)) pending = state.uri.toString();
          return '/demarrage';
        }
        return null;
      }
      if (!session.isSignedIn) {
        if (authPages.contains(location)) return null;
        if (location == '/tv') pending = state.uri.toString();
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
      GoRoute(path: '/demarrage', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/connexion', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/inscription', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/mot-de-passe-oublie',
        builder: (_, state) => PasswordResetScreen(initialEmail: state.extra as String?),
      ),
      GoRoute(path: '/confidentialite', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/a-propos', builder: (_, _) => const AboutScreen()),
      GoRoute(path: '/profils', builder: (_, _) => const ProfilesScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/accueil', pageBuilder: (_, _) => tab(const HomeScreen())),
          GoRoute(
            path: '/films',
            pageBuilder: (_, _) => tab(const HomeScreen(type: MediaType.movie)),
          ),
          GoRoute(
            path: '/series',
            pageBuilder: (_, _) => tab(const HomeScreen(type: MediaType.tv)),
          ),
          GoRoute(
            path: '/recherche',
            pageBuilder: (_, state) => tab(SearchScreen(initialType: state.extra as MediaType?)),
          ),
          GoRoute(path: '/ma-liste', pageBuilder: (_, _) => tab(const MyListScreen())),
          GoRoute(path: '/profil', pageBuilder: (_, _) => tab(const ProfileSettingsScreen())),
          GoRoute(path: '/profil/avatar', builder: (_, _) => const AvatarPickerScreen()),
          GoRoute(path: '/profil/controle-parental', builder: (_, _) => const ParentalControlScreen()),
          GoRoute(path: '/profil/lecture', builder: (_, _) => const PlaybackSettingsScreen()),
          GoRoute(path: '/profil/compte', builder: (_, _) => const AccountScreen()),
          GoRoute(path: '/profil/appareils', builder: (_, _) => const DevicesScreen()),
          GoRoute(
            path: '/personne/:id',
            builder: (_, state) => PersonScreen(id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
          ),
          // Opened by the QR code of a TV: /tv?code=K7F29Q.
          GoRoute(
            path: '/tv',
            builder: (_, state) => DeviceApproveScreen(initialCode: state.uri.queryParameters['code']),
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
        builder: (_, state) => PlayerScreen(
          type: MediaType.parse(state.pathParameters['type']),
          id: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          season: int.tryParse(state.uri.queryParameters['saison'] ?? ''),
          episode: int.tryParse(state.uri.queryParameters['episode'] ?? ''),
        ),
      ),
    ],
    errorBuilder: (context, state) => const Scaffold(
      body: EmptyState(icon: Icons.explore_off_outlined, title: 'Page introuvable'),
    ),
  );
});

/// Shown while the saved session is checked, or when the API cannot be reached.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final unreachable = session.status == SessionStatus.unreachable;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const VxLogo(size: 40),
            const SizedBox(height: 32),
            if (unreachable) ...[
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
            ] else
              const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}
