import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../auth/session.dart';
import '../tmdb/tmdb.dart';
import 'avatars.dart';
import 'profiles_screen.dart';

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
    final tmdb = ref.watch(tmdbAccountProvider).value;
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    if (profile == null) return const SizedBox();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(layout.gutter, 12 * s, layout.gutter, 48 * s),
        children: [
          Text('Paramètres', style: VxText.title(28 * s, weight: FontWeight.w800)),
          SizedBox(height: 28 * s),
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
                subtitle: 'Gérez votre compte, déconnectez-vous ou supprimez-le.',
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
                  icon: Icons.qr_code_scanner_rounded,
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
          SizedBox(height: 28 * s),
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
                icon: Icons.shield_outlined,
                title: 'Contrôle parental',
                subtitle: 'Code parental, profil enfant et âge maximum.',
                onPressed: () => context.push('/profil/controle-parental'),
              ),
              _SettingsTile(
                scale: s,
                icon: Icons.face_rounded,
                title: 'Avatar',
                subtitle: 'Changer l’image de ${profile.name}.',
                onPressed: () => context.push('/profil/avatar'),
              ),
            ],
          ),
          SizedBox(height: 28 * s),
          _SettingsSection(
            label: 'TMDb',
            scale: s,
            children: [
              _SettingsTile(
                scale: s,
                icon: Icons.link_rounded,
                title: 'Compte TMDb',
                subtitle: tmdb?.linked ?? false
                    ? 'Lié à ${tmdb!.displayName}.'
                    : 'Liez votre compte pour noter films, séries et épisodes.',
                onPressed: () => context.push('/profil/tmdb'),
              ),
              if (tmdb?.linked ?? false)
                _SettingsTile(
                  scale: s,
                  icon: Icons.star_outline_rounded,
                  title: 'Mes notes',
                  subtitle: 'Vos notes de films, séries et épisodes, synchronisées avec TMDb.',
                  onPressed: () => context.push('/profil/notes'),
                ),
            ],
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
          padding: EdgeInsets.only(left: 4 * s, bottom: 10 * s),
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

/// Avatar picker, grouped by license.
class AvatarPickerScreen extends ConsumerWidget {
  const AvatarPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final catalog = ref.watch(avatarCatalogProvider);
    final profile = ref.watch(sessionProvider).profile;
    final size = layout.isLarge ? layout.tv(140) : (layout.isPhone ? 84.0 : 100.0);
    final gap = layout.isLarge ? layout.tv(28) : 14.0;

    void pick(String? avatarId) {
      if (avatarId != profile?.avatar) {
        saveProfile(
          context,
          {'avatar': avatarId},
          done: avatarId == null ? 'Avatar retiré' : 'Avatar mis à jour',
          icon: Icons.face_rounded,
        );
      }
      context.pop();
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: VxColors.background,
        title: Text('Choisir un avatar', style: VxText.title(layout.isLarge ? layout.tv(30) : 20)),
      ),
      body: AsyncView(
        value: catalog,
        onRetry: () => ref.invalidate(avatarCatalogProvider),
        data: (licenses) => ListView(
          padding: EdgeInsets.only(bottom: 40, top: layout.isLarge ? layout.tv(16) : 8),
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: _AvatarChoice(
                label: 'Initiale',
                selected: profile?.avatar == null,
                size: size,
                autofocus: profile?.avatar == null,
                onPressed: () => pick(null),
                child: AvatarTile(avatarId: null, initial: profile?.initial ?? '?', size: size),
              ),
            ),
            for (final license in licenses) ...[
              SizedBox(height: layout.isLarge ? layout.tv(36) : 24),
              SectionHeader(license.name),
              FocusTraversalGroup(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final avatar in license.avatars)
                        _AvatarChoice(
                          label: avatar.name,
                          selected: profile?.avatar == avatar.id,
                          size: size,
                          autofocus: profile?.avatar == avatar.id,
                          onPressed: () => pick(avatar.id),
                          child: AvatarTile(avatarId: avatar.id, initial: '?', size: size),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.label,
    required this.selected,
    required this.size,
    required this.onPressed,
    required this.child,
    this.autofocus = false,
  });

  final String label;
  final bool selected;
  final double size;
  final VoidCallback onPressed;
  final Widget child;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + 8,
    child: Column(
      children: [
        VxFocusable(
          autofocus: autofocus,
          borderRadius: size * 0.22,
          focusScale: 1.08,
          semanticLabel: '$label${selected ? ', sélectionné' : ''}',
          onPressed: onPressed,
          child: Stack(
            children: [
              child,
              if (selected)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(size * 0.22),
                      border: Border.all(color: VxColors.accent, width: 3),
                    ),
                  ),
                ),
              if (selected)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    decoration: const BoxDecoration(color: VxColors.accent, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.check_rounded, size: size * 0.18, color: VxColors.onAccent),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: size * 0.08),
        ExcludeSemantics(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: VxText.body(
              (size * 0.14).clamp(11, 22).toDouble(),
              color: selected ? VxColors.accent : VxColors.textSoft,
            ),
          ),
        ),
      ],
    ),
  );
}
