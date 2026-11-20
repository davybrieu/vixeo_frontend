import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/features.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../addons/addons_screen.dart';
import '../auth/session.dart';
import '../notifications/notifications_screen.dart';
import 'advanced_settings_screen.dart';
import 'profiles_screen.dart';
import 'rows_settings_screen.dart';

/// Saves profile fields with the API, refreshes the session and "Qui regarde ?", then
/// confirms with an alert. [context] is only read before the request: the save may end
/// after the screen that asked for it was closed.
Future<bool> saveProfile(
  BuildContext context,
  Map<String, Object?> fields, {
  required String done,
  IconData? icon,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final profile = container.read(sessionProvider).profile;
  if (profile == null) return false;
  try {
    final updated = await container.read(authRepositoryProvider).updateProfile(profile.id, fields);
    container.read(sessionProvider.notifier).updateProfile(updated);
    container.invalidate(profilesProvider);
    showVxSnackOn(messenger, done, icon: icon ?? Icons.check_circle_rounded);
    return true;
  } on ApiException catch (e) {
    showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    return false;
  }
}

/// Settings hub: grouped cards (account / general), using the app's own destinations.
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final profile = ref.watch(sessionProvider).profile;
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    if (profile == null) return const SizedBox();

    // A main page (phone tab): the same header and margins as Recherche, Ma liste and Avis.
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VxPageHeader(title: 'Paramètres'),
          Expanded(
            child: ListView(
              padding: pageContentPadding(context),
              children: [
                _SettingsSection(
                  label: 'Compte',
                  scale: s,
                  children: [
                    _SettingsTile(
                      scale: s,
                      icon: Icons.group_outlined,
                      title: 'Changer de profil',
                      subtitle: 'Basculer vers un autre profil.',
                      onPressed: () => ref.read(sessionProvider.notifier).switchProfile(),
                    ),
                    _SettingsTile(
                      scale: s,
                      icon: Icons.person_outline_rounded,
                      title: 'Compte',
                      subtitle: 'Adresse e-mail, mot de passe, code PIN parental, vos données.',
                      onPressed: () => context.push('/profil/compte'),
                    ),
                    _SettingsTile(
                      scale: s,
                      icon: Icons.devices_rounded,
                      title: 'Appareils',
                      subtitle: 'Voir et déconnecter les appareils liés à ce compte.',
                      onPressed: () => context.push('/profil/appareils'),
                    ),
                    if (!DeviceInfo.isTv)
                      _SettingsTile(
                        scale: s,
                        icon: Icons.tv_rounded,
                        title: 'Connecter une TV',
                        subtitle: 'Approuver le code affiché sur le téléviseur.',
                        onPressed: () => context.push('/tv'),
                      ),
                    _SettingsTile(
                      scale: s,
                      icon: Icons.logout_rounded,
                      title: 'Se déconnecter',
                      subtitle: 'Quitter ce compte sur cet appareil.',
                      foreground: VxColors.dangerText,
                      onPressed: () => ref.read(sessionProvider.notifier).logout(),
                    ),
                  ],
                ),
                SizedBox(height: layout.sectionGap),
                _SettingsSection(
                  label: 'Général',
                  scale: s,
                  children: [
                    _SettingsTile(
                      scale: s,
                      icon: Icons.tune_rounded,
                      title: 'Paramètres',
                      subtitle: 'Apparence, No spoil, langues et lecture automatique.',
                      onPressed: () => context.push('/profil/parametres'),
                    ),
                    _SettingsTile(
                      scale: s,
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Nouveaux épisodes des séries de Ma liste.',
                      onPressed: () => context.push(NotificationsScreen.location),
                    ),
                    _SettingsTile(
                      scale: s,
                      icon: Icons.view_stream_outlined,
                      title: 'Rangées de l’accueil',
                      subtitle: 'Trier, afficher ou masquer les rangées.',
                      onPressed: () => context.push(RowsSettingsScreen.homeLocation),
                    ),
                    // Live TV is hidden for now (core/features.dart).
                    if (ref.watch(liveTvProvider))
                      _SettingsTile(
                        scale: s,
                        icon: Icons.live_tv_outlined,
                        title: 'Catégories des chaînes TV',
                        subtitle: 'Trier, afficher ou masquer les catégories.',
                        onPressed: () => context.push(RowsSettingsScreen.channelsLocation),
                      ),
                    _SettingsTile(
                      scale: s,
                      icon: Icons.extension_outlined,
                      title: 'Plug-ins',
                      subtitle: 'Activer, désactiver et trier les dépôts de sources.',
                      onPressed: () => context.push(AddonsScreen.location),
                    ),
                    _SettingsTile(
                      scale: s,
                      icon: Icons.settings_suggest_outlined,
                      title: 'Avancé',
                      subtitle: 'Démarrage et cache de cet appareil.',
                      onPressed: () => context.push(AdvancedSettingsScreen.location),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.label, required this.scale, required this.children});

  final String label;
  final double scale;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, indent: 72 * s, color: Colors.white.withValues(alpha: 0.06)));
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: Layout.of(context).titleGap),
          child: Text(
            label.toUpperCase(),
            style: VxText.body(13 * s, weight: FontWeight.w700, color: VxColors.textMuted).copyWith(letterSpacing: 1.2),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(22 * s),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22 * s),
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.scale,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.foreground,
  });

  final double scale;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final iconBox = 44.0 * s;
    return VxFocusable(
      borderRadius: 0,
      focusScale: 1.01,
      semanticLabel: '$title. $subtitle',
      onPressed: onPressed,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 14 * s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: iconBox,
              height: iconBox,
              decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(14 * s)),
              child: Icon(icon, size: 22 * s, color: foreground ?? VxColors.text),
            ),
            SizedBox(width: 14 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: VxText.body(16 * s, weight: FontWeight.w600, color: foreground ?? VxColors.text),
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    subtitle,
                    style: VxText.body(13.5 * s, color: foreground ?? VxColors.textSecondary, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
