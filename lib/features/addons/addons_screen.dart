import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../playback/player_screen.dart' show sourceProvidersProvider;
import 'addons.dart';

/// « Plug-ins » (« Paramètres » → « Plug-ins »): the account's plug-ins in the Stremio add-on
/// format (API: `vixeo_backend/docs/plugins.md`). The Vixeo catalog comes first, built in; the
/// plug-ins of every account follow; then the account's own, which it can turn off, move and
/// remove. A new plug-in is installed from the address of its manifest.
///
/// For a Vue developer: a page component whose data comes from a store ([addonsProvider], like a
/// Pinia getter that calls the API), and whose buttons call the repository then refresh it.
class AddonsScreen extends ConsumerStatefulWidget {
  const AddonsScreen({super.key});

  static const location = '/profil/plugins';

  @override
  ConsumerState<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends ConsumerState<AddonsScreen> {
  final _url = TextEditingController();
  String? _urlError;
  bool _installing = false;

  /// The plug-in whose button was just pressed (its buttons wait for the API).
  String? _busy;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  AddonsRepository get _repository => ref.read(addonsRepositoryProvider);

  /// What the plug-ins change elsewhere: the rows of the home, the providers of the player.
  void _refresh() {
    ref
      ..invalidate(addonsProvider)
      ..invalidate(addonSectionsProvider)
      ..invalidate(sourceProvidersProvider);
  }

  Future<void> _install() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = 'Collez l’adresse du plug-in.');
      return;
    }
    setState(() {
      _installing = true;
      _urlError = null;
    });
    try {
      final addon = await _repository.install(url);
      if (!mounted) return;
      _url.clear();
      _refresh();
      showVxSnack(context, 'Plug-in installé : ${addon.name}', icon: Icons.extension_rounded);
    } on ApiException catch (e) {
      if (mounted) setState(() => _urlError = e.field('url') ?? e.message);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  /// Runs [action] for [addon], then refreshes; an error is shown as an alert.
  Future<void> _run(AddonInfo addon, Future<void> Function() action, {String? done}) async {
    setState(() => _busy = addon.id);
    try {
      await action();
      if (!mounted) return;
      _refresh();
      if (done != null) showVxSnack(context, done);
    } on ApiException catch (e) {
      if (mounted) showVxSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _remove(AddonInfo addon) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer le plug-in'),
        content: Text(
          '« ${addon.name} » ne proposera plus de rangées ni de sources. '
          'Vous pourrez le réinstaller avec son adresse.',
          style: VxText.body(15, color: VxColors.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          VxButton(
            label: 'Retirer',
            kind: VxButtonKind.danger,
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _run(addon, () => _repository.remove(addon.id), done: 'Plug-in retiré');
  }

  /// Moves one of the account's own plug-ins among its own ones.
  Future<void> _move(List<AddonInfo> own, int from, int to) {
    final ids = [for (final a in own) a.id];
    ids.insert(to, ids.removeAt(from));
    return _run(own[from], () => _repository.reorder(ids));
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final addons = ref.watch(addonsProvider);

    return InfoPage(
      title: 'Plug-ins',
      fallback: '/profil',
      children: [
        const InfoIntro(
          'Ajoutez des catalogues et des sources au format des add-ons Stremio. '
          'Le catalogue Vixeo est installé par défaut.',
        ),
        InfoSection(
          title: 'Ajouter un plug-in',
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _install(),
              decoration: InputDecoration(
                labelText: 'Adresse du plug-in',
                hintText: 'https://…/manifest.json',
                errorText: _urlError,
                errorMaxLines: 3,
              ),
            ),
            SizedBox(height: layout.listGap),
            VxButton(
              label: 'Installer',
              icon: Icons.add_rounded,
              loading: _installing,
              // On a TV, the field would open the keyboard: the button has the focus first.
              autofocus: true,
              onPressed: _installing ? null : _install,
            ),
          ],
        ),
        InfoSection(
          title: 'Plug-ins installés',
          last: true,
          children: [
            AsyncView(
              value: addons,
              onRetry: () => ref.invalidate(addonsProvider),
              data: (all) {
                final own = [for (final a in all) if (a.editable) a];
                final gap = SizedBox(height: layout.listGap);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, addon) in all.indexed) ...[
                      if (i > 0) gap,
                      _AddonCard(
                        addon: addon,
                        busy: _busy == addon.id,
                        onUp: !addon.editable || own.indexOf(addon) == 0
                            ? null
                            : () => _move(own, own.indexOf(addon), own.indexOf(addon) - 1),
                        onDown: !addon.editable || own.indexOf(addon) == own.length - 1
                            ? null
                            : () => _move(own, own.indexOf(addon), own.indexOf(addon) + 1),
                        onToggle: !addon.editable
                            ? null
                            : () => _run(
                                addon,
                                () => _repository.setEnabled(addon.id, enabled: !addon.enabled),
                                done: addon.enabled ? 'Plug-in désactivé' : 'Plug-in activé',
                              ),
                        onRemove: addon.editable ? () => _remove(addon) : null,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// One plug-in: logo, name and version, what it serves, and its buttons.
class _AddonCard extends StatelessWidget {
  const _AddonCard({
    required this.addon,
    required this.busy,
    required this.onUp,
    required this.onDown,
    required this.onToggle,
    required this.onRemove,
  });

  final AddonInfo addon;
  final bool busy;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onToggle;
  final VoidCallback? onRemove;

  /// What the plug-in serves and where it comes from, on one line.
  String get _facts => [
    if (addon.builtIn) 'Par défaut',
    if (addon.shared) 'Pour tous les comptes',
    if (!addon.enabled) 'Désactivé',
    if (addon.hasCatalogs) addon.catalogs == 1 ? '1 catalogue' : '${addon.catalogs} catalogues',
    if (addon.hasStreams) 'Sources',
    if (addon.host != null) addon.host!,
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final logo = layout.size(44, tv: 72);
    final gap = SizedBox(width: layout.size(6, tv: 14));
    final name = addon.name;

    final actions = <Widget>[
      if (addon.builtIn && addon.manifestUrl != null)
        VxIconAction(
          dense: true,
          icon: Icons.copy_rounded,
          label: 'Copier l’adresse Stremio du catalogue Vixeo',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: addon.manifestUrl!));
            if (context.mounted) showVxSnack(context, 'Adresse copiée', icon: Icons.copy_rounded);
          },
        ),
      if (addon.editable) ...[
        Opacity(
          opacity: onUp == null ? 0.3 : 1,
          child: VxIconAction(
            dense: true,
            icon: Icons.arrow_upward_rounded,
            label: 'Monter : $name',
            onPressed: busy ? null : onUp,
          ),
        ),
        Opacity(
          opacity: onDown == null ? 0.3 : 1,
          child: VxIconAction(
            dense: true,
            icon: Icons.arrow_downward_rounded,
            label: 'Descendre : $name',
            onPressed: busy ? null : onDown,
          ),
        ),
        VxIconAction(
          dense: true,
          icon: addon.enabled ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
          label: addon.enabled ? 'Désactiver : $name' : 'Activer : $name',
          active: addon.enabled,
          onPressed: busy ? null : onToggle,
        ),
        VxIconAction(
          dense: true,
          icon: Icons.delete_outline_rounded,
          label: 'Retirer : $name',
          onPressed: busy ? null : onRemove,
        ),
      ],
    ];

    return VxCard(
      padding: EdgeInsets.symmetric(horizontal: layout.size(14, tv: 24), vertical: layout.size(12, tv: 18)),
      child: Opacity(
        opacity: addon.enabled ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(logo * 0.22),
                  child: SizedBox.square(
                    dimension: logo,
                    child: addon.logoUrl == null
                        ? _LogoFallback(builtIn: addon.builtIn)
                        : NetImage(
                            url: addon.logoUrl,
                            fit: BoxFit.contain,
                            fallback: _LogoFallback(builtIn: addon.builtIn),
                          ),
                  ),
                ),
                SizedBox(width: layout.size(12, tv: 20)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: name),
                            if (addon.version.isNotEmpty)
                              TextSpan(
                                text: '  v${addon.version}',
                                style: VxText.body(12 * s, color: VxColors.textSecondary),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(15 * s, weight: FontWeight.w600),
                      ),
                      if (addon.description != null && addon.description!.isNotEmpty) ...[
                        SizedBox(height: layout.size(2, tv: 4)),
                        Text(
                          addon.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(13 * s, color: VxColors.textSoft),
                        ),
                      ],
                      SizedBox(height: layout.size(4, tv: 6)),
                      Text(
                        _facts,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(12 * s, color: VxColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              SizedBox(height: layout.size(8, tv: 12)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final (i, action) in actions.indexed) ...[if (i > 0) gap, action],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.builtIn});

  final bool builtIn;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: VxColors.surfaceHigh,
    child: Icon(
      builtIn ? Icons.movie_filter_rounded : Icons.extension_rounded,
      color: builtIn ? VxColors.accent : VxColors.textSecondary,
    ),
  );
}
