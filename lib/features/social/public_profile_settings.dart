import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../auth/session.dart';
import '../notifications/inbox.dart' show followRequestsProvider;
import '../profiles/profile_settings_screen.dart' show saveProfile;
import '../profiles/settings_rows.dart';
import 'social_links.dart';
import 'social_repository.dart';

// What the members see on the profile's page, changed from « Paramètres » (developer's request,
// 23/11/2026: no « Modifier le profil » button on the page any more): the biography, the social
// networks and « Compte privé ». The name and the @username are changed in « Qui regarde ? » →
// « Gérer les profils ». Saved by `PUT /profiles/{id}` (vixeo_backend/docs/social.md).
//
// Flutter: each page is a `ConsumerStatefulWidget` (like a Vue component with `data()`): its text
// fields keep what is typed in `TextEditingController`s, created once in `initState` and freed in
// `dispose`.

/// The page of the profile on Vixeo shows the change: it reads the profile again.
void _changed(WidgetRef ref) => ref.invalidate(socialProfileProvider);

/// The profile's public page, for a biography or networks the session doesn't have yet (a profile
/// changed on another device).
Future<SocialProfile?> _publicProfile(WidgetRef ref) async {
  final username = ref.read(sessionProvider).profile?.username ?? '';
  if (username.isEmpty) return null;
  try {
    return await ref.read(socialProfileProvider(username).future);
  } catch (_) {
    return null;
  }
}

/// « Biographie » (`/profil/biographie`): a few words under the name on the profile's page, 160
/// characters at most (the API's limit too).
class BioSettingsScreen extends ConsumerStatefulWidget {
  const BioSettingsScreen({super.key});

  static const location = '/profil/biographie';

  /// Longest biography, in characters (developer's request, 21/11/2026).
  static const maxLength = 160;

  @override
  ConsumerState<BioSettingsScreen> createState() => _BioSettingsScreenState();
}

class _BioSettingsScreenState extends ConsumerState<BioSettingsScreen> {
  final _bio = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bio.text = ref.read(sessionProvider).profile?.bio ?? '';
    if (_bio.text.isEmpty) {
      _publicProfile(ref).then((social) {
        if (mounted && _bio.text.isEmpty) _bio.text = social?.bio ?? '';
      });
    }
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await saveProfile(context, {'bio': _bio.text.trim()}, done: 'Biographie enregistrée');
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      _changed(ref);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return InfoPage(
      title: 'Biographie',
      fallback: '/parametres',
      children: [
        const InfoIntro('Quelques mots sur vous, sous votre nom sur votre profil (160 caractères au plus).'),
        TextField(
          controller: _bio,
          autofocus: !DeviceInfo.isTv,
          maxLength: BioSettingsScreen.maxLength,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Biographie', hintText: 'Fan de science-fiction…'),
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        VxButton(label: 'Enregistrer', icon: Icons.check_rounded, loading: _saving, onPressed: _save),
      ],
    );
  }
}

/// « Réseaux sociaux » (`/profil/reseaux-sociaux`): the profile's accounts (Instagram, X, TikTok,
/// YouTube, Letterboxd, Threads, Bluesky, website), shown under the biography. A username or an
/// address; an emptied field removes the account.
class SocialLinksSettingsScreen extends ConsumerStatefulWidget {
  const SocialLinksSettingsScreen({super.key});

  static const location = '/profil/reseaux-sociaux';

  @override
  ConsumerState<SocialLinksSettingsScreen> createState() => _SocialLinksSettingsScreenState();
}

class _SocialLinksSettingsScreenState extends ConsumerState<SocialLinksSettingsScreen> {
  final _links = {for (final network in SocialNetwork.values) network: TextEditingController()};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fill(ref.read(sessionProvider).profile?.socialLinks ?? const []);
    _publicProfile(ref).then((social) {
      if (mounted) _fill(social?.socialLinks ?? const []);
    });
  }

  /// Fills the empty fields only: what is being typed stays.
  void _fill(List<SocialLink> links) {
    for (final link in links) {
      final field = _links[link.network]!;
      if (field.text.isEmpty) field.text = link.handle;
    }
  }

  @override
  void dispose() {
    for (final field in _links.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await saveProfile(context, {
      // Every network: an emptied field removes its account (null).
      'social_links': {
        for (final MapEntry(key: network, value: field) in _links.entries)
          network.key: field.text.trim().isEmpty ? null : field.text.trim(),
      },
    }, done: 'Réseaux sociaux enregistrés');
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      _changed(ref);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return InfoPage(
      title: 'Réseaux sociaux',
      fallback: '/parametres',
      children: [
        const InfoIntro('Le pseudo ou l’adresse de votre page : ils s’affichent sur votre profil, sous la biographie.'),
        for (final (i, MapEntry(key: network, value: field)) in _links.entries.indexed) ...[
          if (i > 0) SizedBox(height: layout.space(VxSpace.m)),
          TextField(
            controller: field,
            autofocus: i == 0 && !DeviceInfo.isTv,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: network.label,
              hintText: network.isWebsite ? 'https://…' : 'pseudo',
              prefixIcon: Icon(network.icon),
            ),
          ),
        ],
        SizedBox(height: layout.sectionGap),
        VxButton(label: 'Enregistrer', icon: Icons.check_rounded, loading: _saving, onPressed: _save),
      ],
    );
  }
}

/// « Compte privé » (`/profil/compte-prive`): only the followers the profile accepts see its
/// activity, lists, reviews, likes, titles watched, followers and following. Made public, the
/// waiting requests are accepted (the API does it).
class PrivateAccountSettingsScreen extends ConsumerStatefulWidget {
  const PrivateAccountSettingsScreen({super.key});

  static const location = '/profil/compte-prive';

  @override
  ConsumerState<PrivateAccountSettingsScreen> createState() => _PrivateAccountSettingsScreenState();
}

class _PrivateAccountSettingsScreenState extends ConsumerState<PrivateAccountSettingsScreen> {
  bool _saving = false;

  Future<void> _set(bool private) async {
    setState(() => _saving = true);
    final saved = await saveProfile(
      context,
      {'is_private': private},
      done: private ? 'Compte privé activé' : 'Compte public : tout le monde voit votre profil',
      icon: private ? Icons.lock_outline_rounded : Icons.public_rounded,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) {
      _changed(ref);
      if (!private) ref.invalidate(followRequestsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final private = ref.watch(sessionProvider.select((s) => s.profile?.isPrivate ?? false));
    return InfoPage(
      title: 'Compte privé',
      fallback: '/parametres',
      children: [
        const InfoIntro(
          'Un compte privé ne montre son contenu qu’aux abonnés que vous acceptez. Les autres membres voient '
          'seulement votre nom, votre pseudo et votre photo.',
        ),
        SettingsSwitchRow(
          label: 'Compte privé',
          detail:
              'Seuls les abonnés que vous acceptez voient votre activité, vos listes, vos avis, vos J’aime, '
              'vos titres vus, les personnes suivies, vos abonnés et vos abonnements.',
          value: private,
          autofocus: true,
          onChanged: _saving ? null : _set,
        ),
      ],
    );
  }
}
