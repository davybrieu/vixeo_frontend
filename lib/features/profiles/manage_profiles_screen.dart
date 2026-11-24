import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import 'avatars.dart';
import 'profile_editor_screen.dart';
import 'profiles_screen.dart';

/// « Gérer les profils » (« Paramètres » → « Profil »; demande du développeur, 24/11/2026: no
/// longer on « Qui regarde ? »): the account's profiles, the one in use first marked « Profil
/// actuel »; a tap opens « Modifier le profil » (name, pseudo, avatar or photo, restrictions, code,
/// deletion). « Ajouter un profil » while the account has fewer than [maxProfiles].
class ManageProfilesScreen extends ConsumerWidget {
  const ManageProfilesScreen({super.key});

  static const location = '/profil/profils';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final profiles = ref.watch(profilesProvider);
    final active = ref.watch(sessionProvider.select((s) => s.profile?.id));
    return InfoPage(
      title: 'Gérer les profils',
      fallback: '/parametres',
      children: [
        const InfoIntro('Le nom, le pseudo, l’avatar ou la photo, les restrictions et le code de chaque profil.'),
        AsyncView(
          value: profiles,
          onRetry: () => ref.invalidate(profilesProvider),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FocusTraversalGroup(
                policy: vxTraversalPolicy,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, profile) in list.indexed) ...[
                      if (i > 0) SizedBox(height: layout.space(VxSpace.xs)),
                      _ProfileRow(profile: profile, active: profile.id == active, autofocus: i == 0),
                    ],
                  ],
                ),
              ),
              SizedBox(height: layout.sectionGap),
              if (list.length < maxProfiles)
                VxButton(
                  label: 'Ajouter un profil',
                  icon: Icons.person_add_alt_1_rounded,
                  kind: VxButtonKind.secondary,
                  onPressed: () => context.push(ProfileEditorScreen.newLocation),
                )
              else
                Text(
                  '$maxProfiles profils au plus par compte.',
                  style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A profile: round avatar or photo, name, @pseudo or what protects it, a pencil.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.profile, required this.active, this.autofocus = false});

  final Profile profile;
  final bool active;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final avatar = layout.size(52, tv: 84);
    final details = [
      if ((profile.username ?? '').isNotEmpty) '@${profile.username}',
      if (profile.hasPin) 'Protégé par un code',
    ].join(' · ');
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel: [
        'Modifier le profil de ${profile.name}',
        if (active) 'profil actuel',
        if (profile.hasPin) 'protégé par un code',
      ].join(', '),
      onPressed: () => context.push(ProfileEditorScreen.editLocation(profile.id)),
      child: Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
        child: Row(
          children: [
            AvatarTile(
              avatarId: profile.avatar,
              photoUrl: profile.photoUrl,
              initial: profile.initial,
              size: avatar,
              radius: avatar / 2,
            ),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VxText.body(layout.size(16, tv: 24), weight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                        if (active) ...[
                          SizedBox(width: layout.space(VxSpace.xs)),
                          Text(
                            'Profil actuel',
                            style: VxText.body(layout.captionSize, weight: FontWeight.w600, color: VxColors.accent),
                          ),
                        ],
                      ],
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(layout.captionSize, color: VxColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
            Icon(Icons.edit_outlined, size: layout.size(20, tv: 32), color: VxColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
