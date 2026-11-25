import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_loading.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import 'avatars.dart';
import 'pin_pad.dart';
import 'profile_editor_screen.dart';

final profilesProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.read(authRepositoryProvider).profiles();
});

/// Profiles per account, at most (the API refuses a sixth).
const maxProfiles = 5;

/// « Qui regarde ? » (demande du développeur, like other media centers): the title, the round
/// avatars and, while the account has fewer than [maxProfiles], « Ajouter » after them (developer's
/// request, 25/11/2026: « Ajouter un profil »). A profile is changed from the « ⋮ » of its page
/// (« Modifier mon profil »). No logo and no « Se déconnecter » here (it is in « Paramètres » and
/// the « ⋮ »). The back button returns to the profile left with « Changer de profil ».
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  Future<void> _open(Profile profile) async {
    if (profile.hasPin) {
      final pin = await showPinPad(
        context,
        title: 'Saisir le code PIN',
        subtitle: 'Profil de ${profile.name}',
        onSubmit: (pin) async {
          try {
            await ref.read(authRepositoryProvider).verifyProfilePin(profile.id, pin);
            return null;
          } on ApiException catch (e) {
            return e.field('pin') ?? e.message;
          }
        },
      );
      if (pin == null) return;
    }
    await ref.read(sessionProvider.notifier).selectProfile(profile);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final profiles = ref.watch(profilesProvider);
    final large = layout.isLarge;
    final tile = large ? layout.tv(200) : 104.0;
    final previous = ref.read(sessionProvider.notifier).previousProfile;

    // Right after the start-up loading: the same one until the profiles are there.
    if (!profiles.hasValue && !profiles.hasError) return const Scaffold(body: AppLoading());

    return Scaffold(
      body: DecoratedBox(
        // A green glow from the top, as on the other media centers' profile page.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.25),
            radius: 1.25,
            colors: [VxColors.accent.withValues(alpha: 0.26), VxColors.background],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AsyncView(
                        value: profiles,
                        onRetry: () => ref.invalidate(profilesProvider),
                        data: (list) => Center(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.l), horizontal: layout.gutter),
                            child: Column(
                              children: [
                                Text('Qui regarde ?', style: VxText.title(large ? layout.tv(60) : 28)),
                                SizedBox(height: layout.space(VxSpace.xxl)),
                                FocusTraversalGroup(
                                  policy: vxTraversalPolicy,
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: layout.space(VxSpace.xl),
                                    runSpacing: layout.space(VxSpace.l),
                                    children: [
                                      for (final (i, profile) in list.indexed)
                                        _ProfileTile(
                                          profile: profile,
                                          size: tile,
                                          autofocus: i == 0,
                                          onPressed: () => _open(profile),
                                        ),
                                      if (list.length < maxProfiles)
                                        _AddTile(
                                          size: tile,
                                          autofocus: list.isEmpty,
                                          onPressed: () => context.push(ProfileEditorScreen.newLocation),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (previous != null)
                      Positioned(
                        left: layout.gutter - 4,
                        top: 8,
                        child: VxIconAction(
                          icon: Icons.arrow_back_rounded,
                          label: 'Retour au profil de ${previous.name}',
                          dense: true,
                          onPressed: () => ref.read(sessionProvider.notifier).cancelSwitch(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Ajouter »: a round « + » the size of an avatar, its label under it; opens « Ajouter un profil ».
class _AddTile extends StatelessWidget {
  const _AddTile({required this.size, required this.onPressed, this.autofocus = false});

  final double size;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 24,
      child: Column(
        children: [
          VxFocusable(
            autofocus: autofocus,
            onPressed: onPressed,
            borderRadius: size,
            focusScale: 1.08,
            semanticLabel: 'Ajouter un profil',
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: VxColors.text.withValues(alpha: 0.06),
                border: Border.all(color: VxColors.text.withValues(alpha: 0.24), width: size * 0.02),
              ),
              child: Icon(Icons.add_rounded, size: size * 0.42, color: VxColors.textSoft),
            ),
          ),
          SizedBox(height: size * 0.1),
          GestureDetector(
            onTap: onPressed,
            child: ExcludeSemantics(
              child: Text(
                'Ajouter',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: VxText.body(size * 0.14, weight: FontWeight.w600, color: VxColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A profile: its round avatar and its name, a lock when it has a code.
class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, required this.size, required this.onPressed, this.autofocus = false});

  final Profile profile;
  final double size;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.28;
    final label = [profile.name, if (profile.hasPin) 'protégé par un code'].join(', ');
    return SizedBox(
      width: size + 24,
      child: Column(
        children: [
          VxFocusable(
            autofocus: autofocus,
            onPressed: onPressed,
            borderRadius: size,
            focusScale: 1.08,
            semanticLabel: label,
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AvatarTile(
                    avatarId: profile.avatar,
                    photoUrl: profile.photoUrl,
                    initial: profile.initial,
                    size: size,
                    radius: size / 2,
                  ),
                  if (profile.hasPin)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: badge,
                        height: badge,
                        decoration: BoxDecoration(
                          color: VxColors.background,
                          shape: BoxShape.circle,
                          border: Border.all(color: VxColors.background, width: size * 0.025),
                        ),
                        child: Icon(Icons.lock_outline_rounded, size: badge * 0.5, color: VxColors.text),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: size * 0.1),
          // The name under the avatar opens the profile too (touch, mouse).
          GestureDetector(
            onTap: onPressed,
            child: ExcludeSemantics(
              child: Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: VxText.body(size * 0.14, weight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
