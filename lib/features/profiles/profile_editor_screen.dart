import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../notifications/inbox.dart' show followRequestsProvider;
import '../social/social_links.dart';
import '../social/social_repository.dart' show socialProfileProvider;
import 'avatars.dart';
import 'covers.dart';
import 'profile_photo.dart';
import 'profiles_screen.dart';
import 'settings_rows.dart';

/// Longest biography, in characters.
const bioMaxLength = 160;

/// Edit the single profile attached to the signed-in account.
class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen({super.key, required this.profileId, this.onboarding = false, this.registrationTicket});

  final int profileId;
  final bool onboarding;
  final String? registrationTicket;

  static String registrationLocation(String ticket) => '/inscription/profil?ticket=${Uri.encodeComponent(ticket)}';

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

  /// A photo framed here, sent with « Enregistrer ».
  Uint8List? _newPhoto;

  /// The profile's photo is to be removed (« Retirer la photo », or an avatar chosen).
  bool _removePhoto = false;

  /// Cover of the catalog (`GET /covers`).
  String? _cover;

  /// A cover image framed here, sent with « Enregistrer ».
  Uint8List? _newCover;

  /// The profile's cover image is to be removed (« Retirer l'image », or a cover chosen).
  bool _removeCover = false;
  bool _ready = false;
  bool _saving = false;
  ApiException? _error;

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

  /// A profile with a public page: its biography, networks and « Compte privé ».
  bool _hasPage(Profile? profile) => profile != null;

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
    if (profiles == null) return null;
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

  Future<void> _save(Profile? profile) async {
    if (profile == null) return;
    final name = _name.text.trim();
    if (name.isEmpty || (widget.onboarding && _username.text.trim().isEmpty)) return;
    final username = _username.text.trim().toLowerCase();
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(authRepositoryProvider);
    try {
      if (widget.onboarding && profile.id == 0) {
        final ticket = widget.registrationTicket;
        if (ticket == null || _avatar == null || _cover == null) {
          throw ApiException('Choisissez un avatar et une couverture pour continuer.');
        }
        final created = await repository.completeRegistration(
          registrationTicket: ticket,
          profile: {
            'name': name,
            'username': username,
            'bio': _bio.text.trim(),
            'avatar': _avatar,
            'cover': _cover,
            'social_links': {
              for (final entry in _links.entries)
                entry.key.key: entry.value.text.trim().isEmpty ? null : entry.value.text.trim(),
            },
          },
        );
        await ref.read(sessionProvider.notifier).signInWithToken(created.token, created.user);
        if (!mounted) return;
        context.go('/bienvenue');
        return;
      }
      final page = _pageFields(profile);
      final fields = <String, Object?>{
        ...page,
        if (name != profile.name) 'name': name,
        if (username.isNotEmpty && username != profile.username) 'username': username,
        if (_avatar != null && _avatar != profile.avatar) 'avatar': _avatar,
        if (_cover != null && _cover != profile.cover) 'cover': _cover,
      };
      if (fields.isNotEmpty) {
        ref.read(sessionProvider.notifier).updateProfile(await repository.updateProfile(profile.id, fields));
        if (page.isNotEmpty) ref.invalidate(socialProfileProvider);
        if (page['is_private'] == false) ref.invalidate(followRequestsProvider);
      }
      final withPhoto = await _savePhoto(profile.id, profile);
      if (withPhoto != null) ref.read(sessionProvider.notifier).updateProfile(withPhoto);
      final withCover = await _saveCover(profile.id, profile);
      if (withCover != null) ref.read(sessionProvider.notifier).updateProfile(withCover);
      if (widget.onboarding) {
        final completed = await repository.updateProfile(profile.id, {
          'registration_completed': true,
          'name': _name.text.trim(),
          'username': _username.text.trim().toLowerCase(),
          'avatar': _avatar,
          'cover': _cover,
        });
        ref.read(sessionProvider.notifier).updateProfile(completed);
      }
      ref.invalidate(profilesProvider);
      if (!mounted) return;
      showVxSnack(context, widget.onboarding ? 'Profil créé' : 'Modifications enregistrées', icon: Icons.check_circle_outline_rounded);
      if (widget.onboarding) {
        context.go('/bienvenue');
      } else {
        context.pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final layout = Layout.of(context);
    final isNewRegistration = widget.onboarding && widget.registrationTicket != null;
    final profiles = isNewRegistration ? const AsyncData<List<Profile>>([]) : ref.watch(profilesProvider);
    final catalog = ref.watch(avatarCatalogProvider);
    final covers = ref.watch(coverCatalogProvider);
    final existingProfile = _profile(profiles.value);
    final profile = existingProfile ?? (isNewRegistration ? const Profile(id: 0, name: '') : null);
    final gap = layout.sectionGap;

    // Load an existing profile, or initialise an empty registration form without creating a user.
    if (!_ready) {
      if (existingProfile != null) {
        _name.text = existingProfile.name;
        _username.text = existingProfile.username ?? '';
        _avatar = existingProfile.avatar;
        _cover = existingProfile.cover;
        _bio.text = existingProfile.bio ?? '';
        for (final link in existingProfile.socialLinks) {
          _links[link.network]!.text = link.handle;
        }
        _private = existingProfile.isPrivate;
        _ready = true;
      } else if (isNewRegistration) {
        _ready = true;
      }
    }
    final title = widget.onboarding ? 'Complétez votre profil' : 'Modifier mon profil';
    if (profile == null) {
      return InfoPage(
        title: title,
        fallback: '/profil',
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

    return InfoPage(
      title: title,
      fallback: '/profil',
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
                        imageUrl: _removeCover ? null : profile.coverUrl,
                        borderRadius: VxRadius.button * s,
                      ),
              ),
              SizedBox(height: 16 * s),
              Row(
                children: [
                  AvatarTile(
                    avatarId: _avatar,
                    photo: _newPhoto,
                    photoUrl: _removePhoto ? null : profile.photoUrl,
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
                          name.isEmpty ? 'Mon profil' : name,
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
                autofocus: !layout.isLarge,
                maxLength: 50,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                // The preview follows the name.
                onChanged: (_) => setState(() {}),
                style: VxText.body(16 * s),
                decoration: InputDecoration(
                  labelText: 'Nom',
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
                      prefixIcon: FaIcon(network.icon),
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
        if (profile.id != 0 && (canChooseProfilePhoto || _hasPhoto(profile))) ...[
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
          onChoose: profile.id != 0 && canChooseProfilePhoto && !_saving ? _chooseCover : null,
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
        if (error != null && error.fieldErrors.isEmpty) ...[
          SizedBox(height: 16 * s),
          Text(error.message, style: VxText.body(14 * s, color: VxColors.error)),
        ],
        SizedBox(height: gap),
        VxButton(
          label: widget.onboarding ? 'Créer mon compte et continuer' : 'Enregistrer les modifications',
          expand: true,
          loading: _saving,
          onPressed: name.isEmpty || (widget.onboarding && (username.trim().isEmpty || _avatar == null || _cover == null))
              ? null
              : () => _save(profile),
        ),
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
