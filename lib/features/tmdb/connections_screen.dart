import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/card.dart';
import '../account/info_page.dart';
import '../auth/session.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import 'tmdb.dart';

/// "Connexions" (`/profil/connexions`, in Paramètres): the services linked to the profile. Today
/// TMDb, to rate movies, TV shows and episodes: the person approves Vixeo on TMDb's page (opened on
/// a phone / computer, QR code on a large screen), while this page asks the API every few seconds
/// whether it's done; once linked, another account can replace it, or it can be disconnected.
class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  TmdbLinkStart? _pending;
  Timer? _poll;
  bool _checking = false;
  bool _starting = false;
  bool _expired = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from the browser: check at once.
    _lifecycle = AppLifecycleListener(onResume: _check);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  int? get _profileId => ref.read(sessionProvider).profile?.id;

  Future<void> _begin() async {
    final profileId = _profileId;
    if (profileId == null || _starting) return;
    _poll?.cancel();
    setState(() {
      _starting = true;
      _expired = false;
    });
    try {
      final start = await ref.read(tmdbRepositoryProvider).startLink(profileId);
      if (!mounted) return;
      setState(() => _pending = start);
      _poll = Timer.periodic(start.interval, (_) => _check());
      // A large screen shows the QR code (a TV often has no browser).
      if (!Layout.of(context).isLarge) await _open(start.authorizeUrl);
    } on ApiException catch (e) {
      if (mounted) showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _check() async {
    final profileId = _profileId;
    if (_pending == null || _checking || profileId == null) return;
    _checking = true;
    try {
      final account = await ref.read(tmdbRepositoryProvider).completeLink(profileId);
      if (account != null && mounted) {
        _stop();
        ref.read(tmdbAccountProvider.notifier).linked(account);
        showVxSnack(context, 'Compte TMDb lié : ${account.displayName}', icon: Icons.link_rounded);
      }
    } on ApiException catch (e) {
      // 410: the approval page expired. Network hiccups: try again next time.
      if (e.status == 410 && mounted) {
        _stop();
        setState(() => _expired = true);
      }
    } finally {
      _checking = false;
    }
  }

  void _stop() {
    _poll?.cancel();
    _poll = null;
    if (mounted) setState(() => _pending = null);
  }

  Future<void> _open(String url) async {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!opened && mounted) {
      showVxSnack(context, 'Ouvrez ${url.replaceFirst(RegExp(r'^https?://'), '')}', icon: Icons.open_in_new_rounded);
    }
  }

  Future<void> _unlink(TmdbAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Déconnecter le compte TMDb ?'),
        content: Text(
          'Ce profil ne pourra plus noter. Vos notes restent sur TMDb (« ${account.displayName} ») ; vos '
          'commentaires, gardés par Vixeo, seront supprimés.',
          style: VxText.body(15, color: VxColors.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          VxButton(
            label: 'Déconnecter',
            kind: VxButtonKind.danger,
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(tmdbAccountProvider.notifier).unlink();
      if (mounted) showVxSnack(context, 'Compte TMDb déconnecté', icon: Icons.link_off_rounded);
    } on ApiException catch (e) {
      if (mounted) showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(tmdbAccountProvider);
    final s = uiScale(context);

    return InfoPage(
      title: 'Connexions',
      fallback: '/profil',
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12 * s, 0, 12 * s, 16 * s),
          child: Text(
            'Les services liés à ce profil. Vixeo ne voit jamais vos mots de passe : vous autorisez Vixeo sur le '
            'site du service.',
            style: VxText.body(15 * s, color: VxColors.textSecondary),
          ),
        ),
        VxCard(
          child: AsyncView(
            value: account,
            onRetry: () => ref.invalidate(tmdbAccountProvider),
            data: (account) {
              if (_pending != null) return _Waiting(start: _pending!, onOpen: _open, onCancel: _stop);
              return account.linked
                  ? _Linked(account: account, onRelink: _begin, onUnlink: () => _unlink(account), busy: _starting)
                  : _NotLinked(expired: _expired, busy: _starting, onLink: _begin);
            },
          ),
        ),
      ],
    );
  }
}

/// What linking does, said once on each state.
class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return Text(
      'Vos notes sont enregistrées sur TMDb : vous les retrouvez sur tous vos appareils, sur les autres profils '
      'liés au même compte TMDb et sur themoviedb.org.',
      style: VxText.body(15 * s, color: VxColors.textSecondary),
    );
  }
}

class _NotLinked extends StatelessWidget {
  const _NotLinked({required this.expired, required this.busy, required this.onLink});

  final bool expired;
  final bool busy;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TmdbLogo(height: 22 * s),
        SizedBox(height: 18 * s),
        Text('Notez films, séries et épisodes', style: VxText.title(22 * s)),
        SizedBox(height: 8 * s),
        Text(
          'Liez votre compte TMDb à ce profil. Vous autorisez Vixeo sur le site de TMDb : Vixeo ne voit jamais '
          'votre mot de passe.',
          style: VxText.body(15 * s, color: VxColors.textSoft),
        ),
        SizedBox(height: 8 * s),
        const _About(),
        if (expired) ...[
          SizedBox(height: 16 * s),
          Text('La page d’autorisation a expiré. Recommencez.', style: VxText.body(15 * s, color: VxColors.error)),
        ],
        SizedBox(height: 24 * s),
        VxButton(
          label: expired ? 'Recommencer' : 'Lier mon compte TMDb',
          icon: Icons.link_rounded,
          autofocus: true,
          loading: busy,
          onPressed: onLink,
        ),
        SizedBox(height: 16 * s),
        Text(
          'Pas encore de compte ? Créez-le gratuitement sur themoviedb.org.',
          style: VxText.body(13 * s, color: VxColors.textMuted),
        ),
      ],
    );
  }
}

/// Waiting for the approval: QR code on a large screen, TMDb's page opened on a phone.
class _Waiting extends StatelessWidget {
  const _Waiting({required this.start, required this.onOpen, required this.onCancel});

  final TmdbLinkStart start;
  final void Function(String url) onOpen;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final large = Layout.of(context).isLarge;

    final steps = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          large
              ? '1. Scannez ce code avec votre téléphone.\n2. Connectez-vous à TMDb.\n3. Autorisez Vixeo.'
              : '1. Connectez-vous à TMDb sur la page qui vient de s’ouvrir.\n2. Autorisez Vixeo.\n3. Revenez ici.',
          style: VxText.body(16 * s, color: VxColors.textSoft, height: 1.6),
        ),
        SizedBox(height: 18 * s),
        Row(
          children: [
            SizedBox.square(dimension: 18 * s, child: const CircularProgressIndicator(strokeWidth: 2.4)),
            SizedBox(width: 12 * s),
            Flexible(
              child: Text(
                'En attente de votre autorisation…',
                style: VxText.body(15 * s, color: VxColors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Autorisez Vixeo sur TMDb', style: VxText.title(22 * s)),
        SizedBox(height: 18 * s),
        if (large)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                image: true,
                label: 'QR code de la page d’autorisation TMDb',
                excludeSemantics: true,
                child: Container(
                  padding: EdgeInsets.all(10 * s),
                  decoration: BoxDecoration(color: VxColors.text, borderRadius: BorderRadius.circular(14 * s)),
                  child: QrImageView(
                    data: start.authorizeUrl,
                    size: 180 * s,
                    padding: EdgeInsets.zero,
                    backgroundColor: VxColors.text,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: VxColors.background),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: VxColors.background,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 28 * s),
              Expanded(child: steps),
            ],
          )
        else
          steps,
        SizedBox(height: 24 * s),
        Wrap(
          spacing: 12 * s,
          runSpacing: 12 * s,
          children: [
            VxButton(
              label: large ? 'Ouvrir sur cet appareil' : 'Rouvrir la page TMDb',
              icon: Icons.open_in_new_rounded,
              kind: large ? VxButtonKind.secondary : VxButtonKind.primary,
              autofocus: !large,
              onPressed: () => onOpen(start.authorizeUrl),
            ),
            VxButton(label: 'Annuler', kind: VxButtonKind.outline, autofocus: large, onPressed: onCancel),
          ],
        ),
      ],
    );
  }
}

class _Linked extends StatelessWidget {
  const _Linked({required this.account, required this.onRelink, required this.onUnlink, required this.busy});

  final TmdbAccount account;
  final VoidCallback onRelink;
  final VoidCallback onUnlink;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final initial = account.displayName.isEmpty ? '?' : account.displayName.characters.first.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: 56 * s,
                child: NetImage(
                  url: account.avatarUrl,
                  seed: account.accountId ?? 0,
                  fallback: Center(child: Text(initial, style: VxText.title(24 * s))),
                ),
              ),
            ),
            SizedBox(width: 16 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.displayName, style: VxText.title(20 * s)),
                  if (account.username != null && account.username != account.displayName)
                    Text('@${account.username}', style: VxText.body(14 * s, color: VxColors.textSecondary)),
                  if (account.linkedAt != null)
                    Text(
                      'Lié le ${formatFrenchDate(account.linkedAt!)}',
                      style: VxText.body(13 * s, color: VxColors.textMuted),
                    ),
                ],
              ),
            ),
            TmdbLogo(height: 14 * s),
          ],
        ),
        SizedBox(height: 16 * s),
        const _About(),
        SizedBox(height: 24 * s),
        Wrap(
          spacing: 12 * s,
          runSpacing: 12 * s,
          children: [
            VxButton(
              label: 'Changer de compte',
              icon: Icons.swap_horiz_rounded,
              kind: VxButtonKind.outline,
              autofocus: true,
              loading: busy,
              onPressed: onRelink,
            ),
            VxButton(
              label: 'Déconnecter',
              icon: Icons.link_off_rounded,
              kind: VxButtonKind.danger,
              onPressed: onUnlink,
            ),
          ],
        ),
      ],
    );
  }
}
