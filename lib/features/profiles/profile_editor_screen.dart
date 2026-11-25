import 'dart:math';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/choice.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../catalog/catalog_repository.dart';
import '../notifications/inbox.dart' show followRequestsProvider;
import '../social/social_links.dart';
import '../social/social_repository.dart' show socialProfileProvider;
import 'avatars.dart';
import 'covers.dart';
import 'parental_pin.dart';
import 'profile_photo.dart';
import 'pin_pad.dart';
import 'profiles_screen.dart';
import 'settings_rows.dart';

/// Longest biography, in characters (developer's request, 21/11/2026; the API's limit too).
const bioMaxLength = 160;

/// Age limits offered for a profile (null = none).
const ageOptions = <int?>[null, 0, 7, 10, 12, 16, 18];

String ageLabel(int? age) => switch (age) {
  null => 'Aucune limite',
  0 => 'Tous publics',
  final a => '$a ans',
};

/// The age limit that applies: a former « profil enfant » without an age is limited to 10 (API).
int? effectiveMaxAge(Profile profile) => profile.maxAgeRating ?? (profile.isKid ? 10 : null);

/// « Ajouter un profil » (« Ajouter » of « Qui regarde ? ») and « Modifier le profil » (« ⋮ » →
/// « Modifier mon profil » of the profile page; developer's request, 25/11/2026): the avatar, name
/// and pseudo as they will look (under the cover), the name, the pseudo, then for a profile with a
/// page its « Biographie », « Réseaux sociaux » and « Compte privé », « Photo de profil » (its own
/// photo instead of the avatar, demande du développeur, 23/11/2026), the avatars by license,
/// « Couverture » (a cover of the catalog by style, or its own image, 24/11/2026), the restrictions
/// (maximum age, unrated titles; no « profil enfant », demande du développeur), then (to change
/// one) « Sécurité » (the profile's PIN) and « Supprimer le profil ». With parental control on, the
/// parental PIN is asked to create or delete a profile and to change its restrictions
/// (vixeo_backend/docs/controle-parental.md).
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

  /// A few words under the name on the profile's page.
  final _bio = TextEditingController();

  /// Its accounts on social networks: a username or an address each; emptied = removed.
  final _links = {for (final network in SocialNetwork.values) network: TextEditingController()};

  /// « Compte privé »: only the followers it accepts see its page.
  bool _private = false;
  String? _avatar;

  /// A photo framed here, sent with « Enregistrer » / « Créer un profil ».
  Uint8List? _newPhoto;

  /// The profile's photo is to be removed (« Retirer la photo », or an avatar chosen).
  bool _removePhoto = false;

  /// Cover of the catalog (`GET /covers`).
  String? _cover;

  /// A cover image framed here, sent with « Enregistrer » / « Créer un profil ».
  Uint8List? _newCover;

  /// The profile's cover image is to be removed (« Retirer l'image », or a cover chosen).
  bool _removeCover = false;
  int? _maxAge;
  bool _allowUnrated = false;
  bool _ready = false;
  bool _saving = false;
  bool _deleting = false;
  ApiException? _error;

  bool get _creating => widget.profileId == null;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    for (final field in _links.values) {
      field.dispose();
    }
    super.dispose();
  }

  /// A profile with a page on Vixeo (not a child's): its biography, networks and « Compte privé ».
  bool _hasPage(Profile? profile) => profile != null && !profile.isKid;

  /// What changed of its page: `bio`, `social_links` (every network: an emptied field removes its
  /// account) and `is_private`.
  Map<String, Object?> _pageFields(Profile profile) {
    if (!_hasPage(profile)) return const {};
    final bio = _bio.text.trim();
    final links = {
      for (final MapEntry(key: network, value: field) in _links.entries)
        network: field.text.trim().isEmpty ? null : field.text.trim(),
    };
    final before = {for (final link in profile.socialLinks) link.network: link.handle};
    final linksChanged = links.entries.any((e) => e.value != before[e.key]);
    return {
      if (bio != (profile.bio ?? '').trim()) 'bio': bio,
      if (linksChanged) 'social_links': {for (final MapEntry(:key, :value) in links.entries) key.key: value},
      if (_private != profile.isPrivate) 'is_private': _private,
    };
  }

  Profile? _profile(List<Profile>? profiles) {
    if (_creating || profiles == null) return null;
    for (final profile in profiles) {
      if (profile.id == widget.profileId) return profile;
    }
    return null;
  }

  /// The profile shows a photo: a new one, or its own unless removed.
  bool _hasPhoto(Profile? profile) => _newPhoto != null || (!_removePhoto && profile?.photoUrl != null);

  Future<void> _choosePhoto() async {
    final photo = await chooseProfilePhoto(context);
    if (photo == null || !mounted) return;
    setState(() {
      _newPhoto = photo;
      _removePhoto = false;
    });
  }

  /// Sends the photo framed here, or removes the profile's: the profile as the API returns it, or
  /// null when there is nothing to do.
  Future<Profile?> _savePhoto(int profileId, Profile? before) async {
    final repository = ref.read(authRepositoryProvider);
    final photo = _newPhoto;
    if (photo != null) return repository.uploadProfilePhoto(profileId, photo);
    if (_removePhoto && before?.photoUrl != null) return repository.deleteProfilePhoto(profileId);
    return null;
  }

  /// The profile shows a cover image: a new one, or its own unless removed.
  bool _hasCoverImage(Profile? profile) => _newCover != null || (!_removeCover && profile?.coverUrl != null);

  Future<void> _chooseCover() async {
    final cover = await chooseProfileImage(context, FramingShape.cover);
    if (cover == null || !mounted) return;
    setState(() {
      _newCover = cover;
      _removeCover = false;
    });
  }

  /// Sends the cover image framed here, or removes the profile's: the profile as the API returns
  /// it, or null when there is nothing to do.
  Future<Profile?> _saveCover(int profileId, Profile? before) async {
    final repository = ref.read(authRepositoryProvider);
    final cover = _newCover;
    if (cover != null) return repository.uploadProfileCover(profileId, cover);
    if (_removeCover && before?.coverUrl != null) return repository.deleteProfileCover(profileId);
    return null;
  }

  /// The restrictions differ from the profile's (a new profile: from no restriction).
  bool _restrictionsChanged(Profile? profile) => profile == null
      ? _maxAge != null || _allowUnrated
      : _maxAge != effectiveMaxAge(profile) || _allowUnrated != profile.allowUnrated;

  Future<void> _pickAge() async {
    final choice = await showVxChoice<int>(
      context,
      title: 'Âge maximum',
      options: [for (final age in ageOptions) (age, ageLabel(age))],
      selected: _maxAge,
    );
    if (choice != null && mounted) setState(() => _maxAge = choice.$1);
  }

  Future<void> _save(Profile? profile) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    // Without a pseudo, the API makes one from the name.
    final username = _username.text.trim().toLowerCase();
    final restrictions = _restrictionsChanged(profile);
    final parental = ref.read(sessionProvider).user?.parentalControl ?? false;
    String? parentalPin;
    if (parental && (_creating || restrictions)) {
      parentalPin = await askParentalPin(
        context,
        ref,
        reason: _creating ? 'Nécessaire pour créer un profil' : 'Nécessaire pour changer les restrictions',
      );
      if (parentalPin == null) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(authRepositoryProvider);
    try {
      if (_creating) {
        final created = await repository.createProfile(
          name: name,
          username: username,
          avatar: _avatar,
          cover: _cover,
          maxAgeRating: _maxAge,
          allowUnrated: _allowUnrated,
          parentalPin: parentalPin,
        );
        // The profile exists: an image that can't be sent doesn't keep the page (« Créer » again
        // would make a second profile). It can be sent again from « Modifier le profil ».
        String? imageError;
        try {
          await _savePhoto(created.id, null);
        } on ApiException catch (e) {
          imageError = 'la photo n’a pas été envoyée : ${e.field('photo') ?? e.message}';
        }
        try {
          await _saveCover(created.id, null);
        } on ApiException catch (e) {
          imageError ??= 'l’image de couverture n’a pas été envoyée : ${e.field('cover') ?? e.message}';
        }
        ref.invalidate(profilesProvider);
        if (!mounted) return;
        showVxSnack(
          context,
          imageError == null ? 'Profil « $name » créé' : 'Profil « $name » créé, mais $imageError',
          icon: imageError == null ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
        );
        context.pop(true);
        return;
      } else if (profile != null) {
        final page = _pageFields(profile);
        final fields = <String, Object?>{
          ...page,
          if (name != profile.name) 'name': name,
          if (username.isNotEmpty && username != profile.username) 'username': username,
          if (_avatar != null && _avatar != profile.avatar) 'avatar': _avatar,
          if (_cover != null && _cover != profile.cover) 'cover': _cover,
          // A former « profil enfant » becomes a profile with an explicit age limit.
          if (restrictions && profile.isKid) 'is_kid': false,
          if (restrictions && (_maxAge != profile.maxAgeRating || profile.isKid)) 'max_age_rating': _maxAge,
          if (_allowUnrated != profile.allowUnrated) 'allow_unrated': _allowUnrated,
          if (restrictions && parentalPin != null) 'parental_pin': parentalPin,
        };
        if (fields.isNotEmpty) {
          ref.read(sessionProvider.notifier).updateProfile(await repository.updateProfile(profile.id, fields));
          // Its page shows the change; made public, its waiting requests are accepted (the API).
          if (page.isNotEmpty) ref.invalidate(socialProfileProvider);
          if (page['is_private'] == false) ref.invalidate(followRequestsProvider);
        }
        try {
          final withPhoto = await _savePhoto(profile.id, profile);
          if (withPhoto != null) ref.read(sessionProvider.notifier).updateProfile(withPhoto);
          final withCover = await _saveCover(profile.id, profile);
          if (withCover != null) ref.read(sessionProvider.notifier).updateProfile(withCover);
        } on ApiException {
          // The other changes are saved: the page compares the images with the profile read again.
          ref.invalidate(profilesProvider);
          rethrow;
        }
      }
      ref.invalidate(profilesProvider);
      // The catalog is filtered with the active profile's limits: read again.
      if (restrictions) ref.invalidate(homeProvider);
      if (!mounted) return;
      showVxSnack(context, 'Modifications enregistrées', icon: Icons.check_circle_outline_rounded);
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
    if (ref.read(sessionProvider).user?.parentalControl ?? false) {
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
    ref.invalidate(profilesProvider);
    if (!mounted) return;
    final session = ref.read(sessionProvider.notifier);
    showVxSnack(context, 'Profil supprimé', icon: Icons.delete_outline_rounded);
    context.pop(true);
    // The profile in use: « Qui regarde ? » (the router goes there once no profile is chosen).
    await session.forgetProfile(profile.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final layout = Layout.of(context);
    final profiles = ref.watch(profilesProvider);
    final catalog = ref.watch(avatarCatalogProvider);
    final covers = ref.watch(coverCatalogProvider);
    final profile = _profile(profiles.value);
    final gap = layout.sectionGap;

    // The form starts from the profile (to change it), or from an avatar at random (a new one).
    if (!_ready) {
      if (profile != null) {
        _name.text = profile.name;
        _username.text = profile.username ?? '';
        _maxAge = effectiveMaxAge(profile);
        _allowUnrated = profile.allowUnrated;
        _avatar = profile.avatar;
        _cover = profile.cover;
        _bio.text = profile.bio ?? '';
        for (final link in profile.socialLinks) {
          _links[link.network]!.text = link.handle;
        }
        _private = profile.isPrivate;
        _ready = true;
      } else if (_creating && catalog.hasValue) {
        final avatars = [for (final license in catalog.value!) ...license.avatars];
        if (avatars.isNotEmpty) _avatar = avatars[Random().nextInt(avatars.length)].id;
        _ready = true;
      }
    }
    // A new profile: a cover at random too, as the API would give.
    if (_creating && _cover == null && covers.hasValue) {
      final all = [for (final style in covers.value!) ...style.covers];
      if (all.isNotEmpty) _cover = all[Random().nextInt(all.length)].id;
    }

    final title = _creating ? 'Ajouter un profil' : 'Modifier le profil';
    if (!_creating && profile == null) {
      return InfoPage(
        title: title,
        fallback: _creating ? '/profils' : '/profil',
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
      fallback: _creating ? '/profils' : '/profil',
      children: [
        VxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The cover as it will look at the top of the profile page.
              AspectRatio(
                aspectRatio: coverAspectRatio,
                child: _newCover != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(VxRadius.button * s),
                        child: Image.memory(_newCover!, fit: BoxFit.cover, gaplessPlayback: true),
                      )
                    : ProfileCover(
                        coverId: _cover,
                        imageUrl: _removeCover ? null : profile?.coverUrl,
                        borderRadius: VxRadius.button * s,
                      ),
              ),
              SizedBox(height: 16 * s),
              Row(
                children: [
                  AvatarTile(
                    avatarId: _avatar,
                    photo: _newPhoto,
                    photoUrl: _removePhoto ? null : profile?.photoUrl,
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
              if (_hasPage(profile)) ...[
                SizedBox(height: 12 * s),
                TextField(
                  controller: _bio,
                  maxLength: bioMaxLength,
                  minLines: 2,
                  maxLines: 5,
                  style: VxText.body(16 * s),
                  decoration: InputDecoration(
                    labelText: 'Biographie',
                    hintText: 'Fan de science-fiction…',
                    errorText: error?.field('bio'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_hasPage(profile)) ...[
          SizedBox(height: gap),
          VxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Réseaux sociaux', style: VxText.title(17 * s)),
                SizedBox(height: 6 * s),
                Text(
                  'Le pseudo ou l’adresse de votre page : ils s’affichent sur votre profil, sous la biographie.',
                  style: VxText.body(14 * s, color: VxColors.textSecondary),
                ),
                for (final MapEntry(key: network, value: field) in _links.entries) ...[
                  SizedBox(height: 12 * s),
                  TextField(
                    controller: field,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    style: VxText.body(16 * s),
                    decoration: InputDecoration(
                      labelText: network.label,
                      hintText: network.isWebsite ? 'https://…' : 'pseudo',
                      prefixIcon: Icon(network.icon),
                      errorText: error?.field('social_links.${network.key}'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: gap),
          SettingsSection(
            'Confidentialité',
            scale: s,
            last: true,
            children: [
              SettingsSwitchRow(
                label: 'Compte privé',
                detail:
                    'Seuls les abonnés que vous acceptez voient votre activité, vos listes, vos avis, vos J’aime, '
                    'vos titres vus, les personnes suivies, vos abonnés et vos abonnements.',
                value: _private,
                onChanged: (value) => setState(() => _private = value),
              ),
            ],
          ),
        ],
        if (canChooseProfilePhoto || _hasPhoto(profile)) ...[
          SizedBox(height: gap),
          _PhotoCard(
            hasPhoto: _hasPhoto(profile),
            error: error?.field('photo'),
            onChoose: canChooseProfilePhoto && !_saving ? _choosePhoto : null,
            onRemove: _saving
                ? null
                : () => setState(() {
                    _newPhoto = null;
                    _removePhoto = true;
                  }),
          ),
        ],
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
                  // With a photo, no avatar is shown: none is marked.
                  selected: _hasPhoto(profile) ? null : _avatar,
                  // TV: the focus starts on the chosen avatar (a text field would open the keyboard).
                  autofocus: layout.isLarge,
                  // An avatar chosen replaces the photo (« pour laisser le choix »).
                  onPick: (id) => setState(() {
                    _avatar = id;
                    _newPhoto = null;
                    _removePhoto = true;
                  }),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: gap),
        _CoverCard(
          covers: covers,
          // With an image, no cover of the catalog is shown: none is marked.
          selected: _hasCoverImage(profile) ? null : _cover,
          hasImage: _hasCoverImage(profile),
          error: error?.field('cover'),
          onRetry: () => ref.invalidate(coverCatalogProvider),
          onChoose: canChooseProfilePhoto && !_saving ? _chooseCover : null,
          onRemove: _saving
              ? null
              : () => setState(() {
                  _newCover = null;
                  _removeCover = true;
                }),
          // A cover chosen replaces the image.
          onPick: (id) => setState(() {
            _cover = id;
            _newCover = null;
            _removeCover = true;
          }),
        ),
        SizedBox(height: gap),
        // Restrictions of the profile (the « Contrôle parental » page is gone, demande du développeur).
        SettingsSection(
          'Restrictions',
          scale: s,
          last: true,
          children: [
            SettingsChoiceRow(
              icon: Icons.shield_outlined,
              label: 'Âge maximum',
              value: ageLabel(_maxAge),
              onPressed: _pickAge,
            ),
            SettingsSwitchRow(
              label: 'Titres sans classification',
              detail: _maxAge != null
                  ? 'Afficher aussi les titres sans âge conseillé.'
                  : 'Seulement avec une limite d’âge.',
              value: _allowUnrated,
              onChanged: _maxAge != null ? (value) => setState(() => _allowUnrated = value) : null,
            ),
          ],
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

/// « Photo de profil »: import one (framed on « Cadrer la photo »), change it or remove it; the
/// avatar is shown again without it. TV: no import (no files to browse), only « Retirer la photo ».
class _PhotoCard extends StatelessWidget {
  const _PhotoCard({required this.hasPhoto, required this.onChoose, required this.onRemove, this.error});

  final bool hasPhoto;
  final VoidCallback? onChoose;
  final VoidCallback? onRemove;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final error = this.error;
    return VxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Photo de profil', style: VxText.title(17 * s)),
          SizedBox(height: 6 * s),
          Text(
            hasPhoto
                ? 'Votre photo est affichée à la place de l’avatar. Choisir un avatar la retire.'
                : 'Votre propre photo, à la place de l’avatar.',
            style: VxText.body(14 * s, color: VxColors.textSecondary),
          ),
          if (error != null) ...[
            SizedBox(height: 8 * s),
            Text(error, style: VxText.body(14 * s, color: VxColors.error)),
          ],
          SizedBox(height: 14 * s),
          if (canChooseProfilePhoto)
            VxButton(
              label: hasPhoto ? 'Changer la photo' : 'Importer une photo',
              icon: Icons.add_photo_alternate_outlined,
              kind: VxButtonKind.secondary,
              expand: true,
              onPressed: onChoose,
            ),
          if (hasPhoto) ...[
            if (canChooseProfilePhoto) SizedBox(height: 10 * s),
            VxButton(
              label: 'Retirer la photo',
              icon: Icons.hide_image_outlined,
              kind: VxButtonKind.secondary,
              expand: true,
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

/// « Couverture »: the banner at the top of the profile page. Import an image (framed on « Cadrer la
/// couverture »), change it or remove it, or choose a cover of the catalog by style; choosing one
/// removes the image. TV: no import (no files to browse).
class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.covers,
    required this.selected,
    required this.hasImage,
    required this.onPick,
    required this.onRetry,
    this.onChoose,
    this.onRemove,
    this.error,
  });

  final AsyncValue<List<CoverStyle>> covers;
  final String? selected;
  final bool hasImage;
  final ValueChanged<String> onPick;
  final VoidCallback onRetry;
  final VoidCallback? onChoose;
  final VoidCallback? onRemove;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final layout = Layout.of(context);
    final error = this.error;
    final width = layout.isLarge ? layout.tv(270) : 132.0;
    final gap = 12 * s;
    return VxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Couverture', style: VxText.title(17 * s)),
          SizedBox(height: 6 * s),
          Text(
            hasImage
                ? 'Votre image est affichée en haut de votre page. Choisir une couverture la retire.'
                : 'En haut de votre page : une couverture ci-dessous, ou votre propre image.',
            style: VxText.body(14 * s, color: VxColors.textSecondary),
          ),
          if (error != null) ...[
            SizedBox(height: 8 * s),
            Text(error, style: VxText.body(14 * s, color: VxColors.error)),
          ],
          if (canChooseProfilePhoto) ...[
            SizedBox(height: 14 * s),
            VxButton(
              label: hasImage ? 'Changer l’image' : 'Importer une image',
              icon: Icons.add_photo_alternate_outlined,
              kind: VxButtonKind.secondary,
              expand: true,
              onPressed: onChoose,
            ),
          ],
          if (hasImage) ...[
            SizedBox(height: 10 * s),
            VxButton(
              label: 'Retirer l’image',
              icon: Icons.hide_image_outlined,
              kind: VxButtonKind.secondary,
              expand: true,
              onPressed: onRemove,
            ),
          ],
          SizedBox(height: 18 * s),
          AsyncView(
            value: covers,
            onRetry: onRetry,
            data: (styles) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, style) in styles.indexed) ...[
                  if (i > 0) SizedBox(height: 18 * s),
                  Text(style.name, style: VxText.body(13 * s, color: VxColors.textMuted, weight: FontWeight.w600)),
                  SizedBox(height: 10 * s),
                  FocusTraversalGroup(
                    policy: vxTraversalPolicy,
                    child: Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final cover in style.covers)
                          VxFocusable(
                            borderRadius: VxRadius.button * s,
                            focusScale: 1.05,
                            semanticLabel: 'Couverture ${cover.name}${cover.id == selected ? ', choisie' : ''}',
                            onPressed: () => onPick(cover.id),
                            child: Container(
                              padding: EdgeInsets.all(3 * s),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(VxRadius.button * s + 3 * s),
                                border: Border.all(
                                  color: cover.id == selected ? VxColors.accent : Colors.transparent,
                                  width: 3 * s,
                                ),
                              ),
                              child: SizedBox(
                                width: width,
                                height: width / coverAspectRatio,
                                child: ProfileCover(coverId: cover.id, borderRadius: VxRadius.button * s - 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
            policy: vxTraversalPolicy,
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
