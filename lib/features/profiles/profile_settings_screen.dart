import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import 'avatars.dart';
import 'profiles_screen.dart';
import 'no_spoiler.dart';

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

/// "Mon profil": avatar, poster format, switch profile, sign out.
class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final profile = ref.watch(sessionProvider).profile;
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    if (profile == null) return const SizedBox();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(layout.gutter, 16 * s, layout.gutter, 40 * s),
        children: [
          Text('Mon profil', style: VxText.title(28 * s)),
          SizedBox(height: 24 * s),
          Row(
            children: [
              ProfileAvatar(profile: profile, size: 96 * s),
              SizedBox(width: 20 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: VxText.title(24 * s)),
                    if (profile.isKid) ...[SizedBox(height: 6 * s), VxBadge('Profil enfant', fontSize: 12 * s)],
                    SizedBox(height: 12 * s),
                    VxButton(
                      label: 'Changer d’avatar',
                      icon: Icons.face_rounded,
                      kind: VxButtonKind.secondary,
                      autofocus: true,
                      onPressed: () => context.push('/profil/avatar'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 36 * s),
          Text('Format des affiches', style: VxText.title(18 * s)),
          SizedBox(height: 6 * s),
          Text(
            'Comment les films et séries s’affichent dans les rangées et les listes.',
            style: VxText.body(14 * s, color: VxColors.textSecondary),
          ),
          SizedBox(height: 16 * s),
          FocusTraversalGroup(
            child: Wrap(
              spacing: 14 * s,
              runSpacing: 14 * s,
              children: [
                for (final format in PosterFormat.values)
                  _FormatOption(
                    format: format,
                    selected: profile.posterFormat == format,
                    scale: s,
                    onPressed: () {
                      if (profile.posterFormat == format) return;
                      saveProfile(
                        context,
                        {'poster_format': format.name},
                        done: 'Affiches au format ${format.label.toLowerCase()}',
                        icon: Icons.view_carousel_rounded,
                      );
                    },
                  ),
              ],
            ),
          ),
          SizedBox(height: 28 * s),
          Text('Affichage', style: VxText.title(18 * s)),
          SizedBox(height: 8 * s),
          _NoSpoilerSetting(scale: s),
          SizedBox(height: 36 * s),
          Text('Profil', style: VxText.title(18 * s)),
          SizedBox(height: 14 * s),
          Wrap(
            spacing: 12 * s,
            runSpacing: 12 * s,
            children: [
              VxButton(
                label: 'Lecture et sous-titres',
                icon: Icons.subtitles_outlined,
                kind: VxButtonKind.outline,
                onPressed: () => context.push('/profil/lecture'),
              ),
              VxButton(
                label: 'Contrôle parental',
                icon: Icons.shield_outlined,
                kind: VxButtonKind.outline,
                onPressed: () => context.push('/profil/controle-parental'),
              ),
              // A TV signs in with its own QR code; this is for phones, tablets and computers.
              if (!DeviceInfo.isTv)
                VxButton(
                  label: 'Connecter une TV',
                  icon: Icons.qr_code_scanner_rounded,
                  kind: VxButtonKind.outline,
                  onPressed: () => context.push('/tv'),
                ),
              VxButton(
                label: 'Changer de profil',
                icon: Icons.switch_account_rounded,
                kind: VxButtonKind.outline,
                onPressed: () => ref.read(sessionProvider.notifier).switchProfile(),
              ),
              VxButton(
                label: 'Se déconnecter',
                icon: Icons.logout_rounded,
                kind: VxButtonKind.outline,
                onPressed: () => ref.read(sessionProvider.notifier).logout(),
              ),
            ],
          ),
          SizedBox(height: 36 * s),
          Text('Compte et confidentialité', style: VxText.title(18 * s)),
          SizedBox(height: 14 * s),
          Wrap(
            spacing: 12 * s,
            runSpacing: 12 * s,
            children: [
              VxButton(
                label: 'Mon compte',
                icon: Icons.manage_accounts_outlined,
                kind: VxButtonKind.outline,
                onPressed: () => context.push('/profil/compte'),
              ),
              VxButton(
                label: 'Appareils connectés',
                icon: Icons.devices_rounded,
                kind: VxButtonKind.outline,
                onPressed: () => context.push('/profil/appareils'),
              ),
              VxButton(
                label: 'Confidentialité',
                icon: Icons.privacy_tip_outlined,
                kind: VxButtonKind.outline,
                onPressed: () => context.push('/confidentialite'),
              ),
              VxButton(
                label: 'Aide et à propos',
                icon: Icons.help_outline_rounded,
                kind: VxButtonKind.outline,
                onPressed: () => context.push('/a-propos'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vertical / horizontal choice, with a small preview.
class _FormatOption extends StatelessWidget {
  const _FormatOption({required this.format, required this.selected, required this.scale, required this.onPressed});

  final PosterFormat format;
  final bool selected;
  final double scale;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final portrait = format == PosterFormat.portrait;
    Widget tile(int i) => Container(
      width: portrait ? 30 * s : 56 * s,
      height: portrait ? 45 * s : 32 * s,
      decoration: BoxDecoration(
        color: VxColors.tone(i + (portrait ? 1 : 4)),
        borderRadius: BorderRadius.circular(5 * s),
      ),
    );

    return VxFocusable(
      borderRadius: 16 * s,
      semanticLabel: 'Format ${format.label.toLowerCase()}${selected ? ', sélectionné' : ''}',
      onPressed: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 170 * s,
        padding: EdgeInsets.all(16 * s),
        decoration: BoxDecoration(
          color: selected ? VxColors.accent.withValues(alpha: 0.1) : VxColors.surface,
          borderRadius: BorderRadius.circular(16 * s),
          border: Border.all(color: selected ? VxColors.accent : VxColors.line, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 48 * s,
              child: Row(
                children: [
                  for (var i = 0; i < (portrait ? 3 : 2); i++) ...[if (i > 0) SizedBox(width: 6 * s), tile(i)],
                ],
              ),
            ),
            SizedBox(height: 12 * s),
            Row(
              children: [
                Expanded(
                  child: Text(format.label, style: VxText.body(15 * s, weight: FontWeight.w600)),
                ),
                if (selected) Icon(Icons.check_circle_rounded, color: VxColors.accent, size: 20 * s),
              ],
            ),
            Text(
              portrait ? 'Affiche (par défaut)' : 'Image large',
              style: VxText.body(12 * s, color: VxColors.textSecondary),
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
        // Starts the save (it keeps what it needs), then closes the picker right away.
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


class _NoSpoilerSetting extends ConsumerWidget {
  const _NoSpoilerSetting({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(noSpoilerProvider);
    return VxFocusable(
      borderRadius: 14 * scale,
      focusScale: 1.02,
      semanticLabel: 'No spoil, ${enabled ? 'activé' : 'désactivé'}',
      onPressed: () => saveProfile(
        context,
        {'no_spoiler': !enabled},
        done: !enabled ? 'No spoil activé' : 'No spoil désactivé',
        icon: Icons.visibility_off_outlined,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
        decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(14 * scale)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No spoil', style: VxText.body(15 * scale, weight: FontWeight.w600)),
                  SizedBox(height: 2 * scale),
                  Text(
                    'Floute les images, titres et descriptions des épisodes.',
                    style: VxText.body(13 * scale, color: VxColors.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12 * scale),
            IgnorePointer(
              child: ExcludeFocus(
                child: Transform.scale(
                  scale: scale,
                  child: Switch(value: enabled, onChanged: (_) {}, activeThumbColor: VxColors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
