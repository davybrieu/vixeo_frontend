import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import 'avatars.dart';
import 'pin_pad.dart';
import 'profiles_screen.dart';

/// « Ajouter un profil » and « Modifier le profil », opened from « Qui regarde ? » →
/// « Gérer les profils » (demande du développeur, like other media centers): the avatar, name and
/// pseudo as they will look, the name, the pseudo, the avatars by license, then (to change one) « Sécurité » (the
/// profile's PIN) and « Supprimer le profil ». The parental PIN is asked when parental control is
/// on to create or delete a profile (vixeo_backend/docs/controle-parental.md).
class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen({super.key, this.profileId});

  /// Null: a new profile.
  final int? profileId;

  static const newLocation = '/profils/nouveau';

  static String editLocation(int id) => '/profils/modifier/$id';

  @override
  ConsumerState<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  String? _avatar;
  bool _ready = false;
  bool _saving = false;
  bool _deleting = false;
  ApiException? _error;

  bool get _creating => widget.profileId == null;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Profile? _profile(List<Profile>? profiles) {
    if (_creating || profiles == null) return null;
    for (final profile in profiles) {
      if (profile.id == widget.profileId) return profile;
    }
    return null;
  }

  bool get _parental => ref.read(sessionProvider).user?.parentalControl ?? false;

  /// The parental PIN, checked by the API, or null when the person closes the keypad.
  Future<String?> _parentalPin(String reason) => showPinPad(
    context,
    title: 'Code PIN parental',
    subtitle: reason,
    onSubmit: (pin) async {
      try {
        await ref.read(authRepositoryProvider).verifyParentalPin(pin);
        return null;
      } on ApiException catch (e) {
        return e.field('pin') ?? e.message;
      }
    },
  );

  Future<void> _save(Profile? profile) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    // Without a pseudo, the API makes one from the name.
    final username = _username.text.trim().toLowerCase();
    String? parentalPin;
    if (_creating && _parental) {
      parentalPin = await _parentalPin('Nécessaire pour créer un profil');
      if (parentalPin == null) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(authRepositoryProvider);
    try {
      if (_creating) {
        await repository.createProfile(name: name, username: username, avatar: _avatar, parentalPin: parentalPin);
      } else if (profile != null) {
        final fields = <String, Object?>{
          if (name != profile.name) 'name': name,
          if (username.isNotEmpty && username != profile.username) 'username': username,
          if (_avatar != null && _avatar != profile.avatar) 'avatar': _avatar,
        };
        if (fields.isNotEmpty) {
          ref.read(sessionProvider.notifier).updateProfile(await repository.updateProfile(profile.id, fields));
        }
      }
      ref.invalidate(profilesProvider);
      if (!mounted) return;
      showVxSnack(
        context,
        _creating ? 'Profil « $name » créé' : 'Modifications enregistrées',
        icon: Icons.check_circle_outline_rounded,
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Turns the profile's PIN on (typed twice) or off (the current one).
  Future<void> _pin(Profile profile) async {
    final repository = ref.read(authRepositoryProvider);
    final on = !profile.hasPin;
    final pin = await showPinPad(
      context,
      title: 'Saisir le code PIN',
      subtitle: on ? 'Saisir un nouveau code PIN' : 'Supprimer le code PIN de ${profile.name}',
      confirm: on,
      onSubmit: (pin) async {
        try {
          final updated = await repository.updateProfile(
            profile.id,
            on ? {'pin': pin} : {'pin': null, 'current_pin': pin},
          );
          ref.read(sessionProvider.notifier).updateProfile(updated);
          return null;
        } on ApiException catch (e) {
          return e.field('current_pin') ?? e.field('pin') ?? e.message;
        }
      },
    );
    if (pin == null || !mounted) return;
    ref.invalidate(profilesProvider);
    showVxSnack(
      context,
      on ? 'Le profil est protégé par un code PIN' : 'Code PIN supprimé',
      icon: on ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
    );
  }

  Future<void> _delete(Profile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le profil'),
        content: Text(
          'Toutes les données de « ${profile.name} » seront définitivement supprimées.',
          style: VxText.body(15, color: VxColors.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          VxButton(
            label: 'Supprimer',
            kind: VxButtonKind.danger,
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final repository = ref.read(authRepositoryProvider);
    if (_parental) {
      // The keypad's check is the deletion itself.
      final pin = await showPinPad(
        context,
        title: 'Code PIN parental',
        subtitle: 'Nécessaire pour supprimer un profil',
        onSubmit: (pin) async {
          try {
            await repository.deleteProfile(profile.id, parentalPin: pin);
            return null;
          } on ApiException catch (e) {
            return e.field('parental_pin') ?? e.message;
          }
        },
      );
      if (pin == null) return;
    } else {
      setState(() => _deleting = true);
      try {
        await repository.deleteProfile(profile.id);
      } on ApiException catch (e) {
        if (mounted) {
          setState(() => _deleting = false);
          showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
        }
        return;
      }
    }
    ref.read(sessionProvider.notifier).forgetProfile(profile.id);
    ref.invalidate(profilesProvider);
    if (!mounted) return;
    showVxSnack(context, 'Profil supprimé', icon: Icons.delete_outline_rounded);
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final layout = Layout.of(context);
    final profiles = ref.watch(profilesProvider);
    final catalog = ref.watch(avatarCatalogProvider);
    final profile = _profile(profiles.value);
    final gap = layout.sectionGap;

    // The form starts from the profile (to change it), or from an avatar at random (a new one).
    if (!_ready) {
      if (profile != null) {
        _name.text = profile.name;
        _username.text = profile.username ?? '';
        _avatar = profile.avatar;
        _ready = true;
      } else if (_creating && catalog.hasValue) {
        final avatars = [for (final license in catalog.value!) ...license.avatars];
        if (avatars.isNotEmpty) _avatar = avatars[Random().nextInt(avatars.length)].id;
        _ready = true;
      }
    }

    final title = _creating ? 'Ajouter un profil' : 'Modifier le profil';
    if (!_creating && profile == null) {
      return InfoPage(
        title: title,
        fallback: '/profils',
        children: [
          if (profiles.isLoading)
            const Center(child: CircularProgressIndicator())
          else
            const InfoIntro('Ce profil n’existe plus.'),
        ],
      );
    }

    final name = _name.text.trim();
    final username = _username.text.trim();
    final error = _error;
    final canDelete = (profiles.value?.length ?? 0) > 1;

    return InfoPage(
      title: title,
      fallback: '/profils',
      children: [
        VxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AvatarTile(
                    avatarId: _avatar,
                    initial: name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    size: 64 * s,
                    radius: 32 * s,
                  ),
                  SizedBox(width: 16 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Nouveau profil' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.title(18 * s),
                        ),
                        if (username.isNotEmpty)
                          Text(
                            '@$username',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VxText.body(13 * s, color: VxColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16 * s),
              TextField(
                controller: _name,
                autofocus: _creating && !layout.isLarge,
                maxLength: 50,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                // The preview and « Créer un profil » follow the name.
                onChanged: (_) => setState(() {}),
                style: VxText.body(16 * s),
                decoration: InputDecoration(
                  labelText: 'Nom du profil',
                  counterText: '',
                  errorText: error?.field('name'),
                ),
              ),
              SizedBox(height: 12 * s),
              TextField(
                controller: _username,
                maxLength: 30,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                // The preview follows the pseudo.
                onChanged: (_) => setState(() {}),
                style: VxText.body(16 * s),
                decoration: InputDecoration(
                  labelText: 'Pseudo',
                  prefixText: '@',
                  counterText: '',
                  errorText: error?.field('username'),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: gap),
        VxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Choisir un avatar', style: VxText.title(17 * s)),
              SizedBox(height: 12 * s),
              AsyncView(
                value: catalog,
                onRetry: () => ref.invalidate(avatarCatalogProvider),
                data: (licenses) => _AvatarGrid(
                  licenses: licenses,
                  selected: _avatar,
                  // TV: the focus starts on the chosen avatar (a text field would open the keyboard).
                  autofocus: layout.isLarge,
                  onPick: (id) => setState(() => _avatar = id),
                ),
              ),
            ],
          ),
        ),
        if (profile != null) ...[
          SizedBox(height: gap),
          VxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Sécurité', style: VxText.title(17 * s)),
                SizedBox(height: 6 * s),
                Text(
                  profile.hasPin
                      ? 'Ce profil est protégé par un code PIN.'
                      : 'Ajoutez un code PIN pour que ce profil soit verrouillé avant d’y accéder.',
                  style: VxText.body(14 * s, color: VxColors.textSecondary),
                ),
                SizedBox(height: 14 * s),
                VxButton(
                  // Short: the whole label fits on a phone.
                  label: profile.hasPin ? 'Retirer le code PIN' : 'Ajouter un code PIN',
                  icon: profile.hasPin ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  kind: VxButtonKind.secondary,
                  expand: true,
                  onPressed: () => _pin(profile),
                ),
              ],
            ),
          ),
        ],
        if (error != null && error.fieldErrors.isEmpty) ...[
          SizedBox(height: 16 * s),
          Text(error.message, style: VxText.body(14 * s, color: VxColors.error)),
        ],
        SizedBox(height: gap),
        VxButton(
          label: _creating ? 'Créer un profil' : 'Enregistrer les modifications',
          expand: true,
          loading: _saving,
          onPressed: name.isEmpty || _deleting ? null : () => _save(profile),
        ),
        if (profile != null && canDelete) ...[
          SizedBox(height: 12 * s),
          VxButton(
            label: 'Supprimer le profil',
            icon: Icons.delete_outline_rounded,
            kind: VxButtonKind.danger,
            expand: true,
            loading: _deleting,
            onPressed: _saving ? null : () => _delete(profile),
          ),
        ],
      ],
    );
  }
}

/// The avatars of the catalog by license, round; the chosen one has a green ring.
class _AvatarGrid extends StatelessWidget {
  const _AvatarGrid({required this.licenses, required this.selected, required this.onPick, this.autofocus = false});

  final List<AvatarLicense> licenses;
  final String? selected;
  final ValueChanged<String> onPick;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final size = layout.isLarge ? layout.tv(110) : 60.0;
    final gap = 12 * s;
    final hasSelected = licenses.any((l) => l.avatars.any((a) => a.id == selected));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, license) in licenses.indexed) ...[
          if (i > 0) SizedBox(height: 18 * s),
          Text(license.name, style: VxText.body(13 * s, color: VxColors.textMuted, weight: FontWeight.w600)),
          SizedBox(height: 10 * s),
          FocusTraversalGroup(
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (j, avatar) in license.avatars.indexed)
                  VxFocusable(
                    autofocus: autofocus && (hasSelected ? avatar.id == selected : i == 0 && j == 0),
                    borderRadius: size,
                    focusScale: 1.08,
                    semanticLabel: '${avatar.name}${avatar.id == selected ? ', choisi' : ''}',
                    onPressed: () => onPick(avatar.id),
                    child: Container(
                      padding: EdgeInsets.all(3 * s),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: avatar.id == selected ? VxColors.accent : Colors.transparent,
                          width: 3 * s,
                        ),
                      ),
                      child: AvatarTile(avatarId: avatar.id, initial: '?', size: size, radius: size / 2),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
