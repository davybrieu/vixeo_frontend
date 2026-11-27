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
import '../notifications/inbox.dart' show socialAvailable;
import '../notifications/notifications_screen.dart';
import 'profile_editor_screen.dart';
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

/// Settings hub: grouped cards (account, general), using the app's own destinations. The profile
/// is changed, and the account left, from the « ⋮ » of its page (« Modifier mon profil »,
/// « Changer de profil », « Comptes bloqués et masqués », « Se déconnecter »: developer's request,
/// 25/11/2026; no « Profil », « Avancé » nor « Se déconnecter » here any more). A child's profile
/// has no page: « Changer de profil » and « Modifier le profil » stay here for it.
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final profile = ref.watch(sessionProvider).profile;
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    if (profile == null) return const SizedBox();
    final withPage = socialAvailable(ref.watch(sessionProvider));

    // A main page (phone tab): the same header and margins as Recherche, À voir and Avis.
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // On a phone, a profile with a page opens « Paramètres » from it (not a tab): back button.
          VxPageHeader(title: 'Paramètres', back: layout.isPhone && withPage),
          Expanded(
            child: ListView(
              padding: pageContentPadding(context),
              children: [
                if (!withPage) ...[
                  _SettingsSection(
                    label: 'Profil',
                    scale: s,
                    children: [
                      _SettingsTile(
                        scale: s,
                        icon: Icons.edit_outlined,
                        title: 'Modifier le profil',
                        subtitle: 'Nom, pseudo, avatar, photo et couverture.',
                        onPressed: () => context.push(ProfileEditorScreen.editLocation(profile.id)),
                      ),
                    ],
                  ),
                  SizedBox(height: layout.sectionGap),
                ],
                _SettingsSection(
                  label: 'Compte',
                  scale: s,
                  children: [
                    _SettingsTile(
                      scale: s,
                      icon: Icons.person_outline_rounded,
                      title: 'Compte',
                      subtitle: 'Adresse e-mail, mot de passe et vos données.',
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
                      subtitle: 'No spoil, langues, lecture automatique, note à la fin.',
                      onPressed: () => context.push('/profil/parametres'),
                    ),
                    _SettingsTile(
                      scale: s,
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Nouveaux épisodes des séries « À voir », activité.',
                      onPressed: () => context.push(NotificationsScreen.location),
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
  });

  final double scale;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

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
              child: Icon(icon, size: 22 * s, color: VxColors.text),
            ),
            SizedBox(width: 14 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: VxText.body(16 * s, weight: FontWeight.w600, color: VxColors.text),
                  ),
                  SizedBox(height: 2 * s),
                  Text(
                    subtitle,
                    style: VxText.body(13.5 * s, color: VxColors.textSecondary, height: 1.3),
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
