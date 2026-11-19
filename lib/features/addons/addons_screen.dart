import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../account/info_page.dart';
import '../playback/player_screen.dart' show sourceProvidersProvider;
import 'scraper_models.dart';
import 'scrapers.dart';

/// « Plug-ins » (« Paramètres » → « Plug-ins »), façon Nuvio (`docs/scrapers.md`): the person adds
/// the address of a **repository** (a `manifest.json` somebody hosts) and gets its **scrapers**,
/// JavaScript that finds the streams of a title. They appear in the sources panel of the player,
/// never as rows or titles (the catalog stays TMDb's). Each scraper can be turned off, moved, and
/// run on the device or on the server.
///
/// Vixeo provides no repository: the page says so, and nothing is installed by default.
///
/// For a Vue developer: a page component whose data comes from a store ([scraperReposProvider],
/// like a Pinia store), and whose buttons call the store's actions.
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

  /// What was just pressed (a scraper's key or a repository's id): its buttons wait for the answer.
  String? _busy;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  ScraperRepos get _repos => ref.read(scraperReposProvider.notifier);

  /// What the plug-ins change elsewhere: the providers of the player's sources panel.
  void _refreshSources() => ref.invalidate(sourceProvidersProvider);

  Future<void> _install() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = "Collez l'adresse du dépôt.");
      return;
    }
    setState(() {
      _installing = true;
      _urlError = null;
    });
    try {
      final repo = await _repos.add(url);
      if (!mounted) return;
      _url.clear();
      _refreshSources();
      showVxSnack(context, 'Dépôt installé : ${repo.name}', icon: Icons.extension_rounded);
    } on ScraperException catch (e) {
      if (mounted) setState(() => _urlError = e.message);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  /// Runs [action] for what [busy] names, then refreshes; an error is shown as an alert.
  Future<void> _run(String busy, Future<void> Function() action, {String? done}) async {
    setState(() => _busy = busy);
    try {
      await action();
      if (!mounted) return;
      _refreshSources();
      if (done != null) showVxSnack(context, done);
    } on ScraperException catch (e) {
      if (mounted) showVxSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _removeRepo(ScraperRepo repo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer le dépôt'),
        content: Text(
          '« ${repo.name} » et ses plug-ins ne proposeront plus de sources. '
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
    if (ok == true && mounted) await _run(repo.id, () => _repos.remove(repo.id), done: 'Dépôt retiré');
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final repos = ref.watch(scraperReposProvider);

    return InfoPage(
      title: 'Plug-ins',
      fallback: '/profil',
      children: [
        const InfoIntro(
          'Ajoutez l’adresse d’un dépôt : chaque plug-in qu’il contient apporte des sources au choix des '
          'sources du lecteur. Vixeo n’en fournit aucun, vous êtes responsable des dépôts que vous ajoutez.',
        ),
        InfoSection(
          title: 'Ajouter un dépôt',
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _install(),
              decoration: InputDecoration(
                labelText: 'Adresse du dépôt',
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
          title: 'Dépôts installés',
          last: true,
          children: [
            AsyncView(
              value: repos,
              onRetry: () => ref.invalidate(scraperReposProvider),
              data: (all) {
                if (all.isEmpty) {
                  return Text('Aucun dépôt installé.', style: VxText.body(15, color: VxColors.textSoft));
                }
                final gap = SizedBox(height: layout.sectionGap);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, repo) in all.indexed) ...[
                      if (i > 0) gap,
                      _RepoView(
                        repo: repo,
                        busy: _busy,
                        onRefresh: () => _run(repo.id, () => _repos.refresh(repo.id), done: 'Dépôt mis à jour'),
                        onRemove: () => _removeRepo(repo),
                        onMove: (from, to) => _run(repo.scrapers[from].key, () => _repos.move(repo.id, from, to)),
                        onToggle: (scraper) => _run(
                          scraper.key,
                          () => _repos.setEnabled(scraper.key, enabled: !scraper.enabled),
                          done: scraper.enabled ? 'Plug-in désactivé' : 'Plug-in activé',
                        ),
                        onMode: (scraper) => _run(
                          scraper.key,
                          () => _repos.setMode(
                            scraper.key,
                            scraper.mode == ScraperMode.device ? ScraperMode.server : ScraperMode.device,
                          ),
                          done: scraper.mode == ScraperMode.device
                              ? 'S’exécutera sur le serveur'
                              : 'S’exécutera sur l’appareil',
                        ),
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

/// One repository: its header, then its scrapers.
class _RepoView extends StatelessWidget {
  const _RepoView({
    required this.repo,
    required this.busy,
    required this.onRefresh,
    required this.onRemove,
    required this.onMove,
    required this.onToggle,
    required this.onMode,
  });

  final ScraperRepo repo;
  final String? busy;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;
  final void Function(int from, int to) onMove;
  final void Function(ScraperInfo scraper) onToggle;
  final void Function(ScraperInfo scraper) onMode;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final count = repo.scrapers.length;
    final facts = [repo.host, '$count plug-in${count > 1 ? 's' : ''}'].join(' · ');
    final repoBusy = busy == repo.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(16 * s, weight: FontWeight.w700),
                  ),
                  Text(
                    facts,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(12 * s, color: VxColors.textSecondary),
                  ),
                ],
              ),
            ),
            VxIconAction(
              dense: true,
              icon: Icons.sync_rounded,
              label: 'Mettre à jour le dépôt : ${repo.name}',
              onPressed: repoBusy ? null : onRefresh,
            ),
            SizedBox(width: layout.size(6, tv: 14)),
            VxIconAction(
              dense: true,
              icon: Icons.delete_outline_rounded,
              label: 'Retirer le dépôt : ${repo.name}',
              onPressed: repoBusy ? null : onRemove,
            ),
          ],
        ),
        SizedBox(height: layout.listGap),
        for (final (i, scraper) in repo.scrapers.indexed) ...[
          if (i > 0) SizedBox(height: layout.listGap),
          _ScraperCard(
            scraper: scraper,
            busy: busy == scraper.key || repoBusy,
            onUp: i == 0 ? null : () => onMove(i, i - 1),
            onDown: i == count - 1 ? null : () => onMove(i, i + 1),
            onToggle: () => onToggle(scraper),
            onMode: () => onMode(scraper),
          ),
        ],
      ],
    );
  }
}

/// One scraper: logo, name and version, what it serves and where it runs, and its buttons.
class _ScraperCard extends StatelessWidget {
  const _ScraperCard({
    required this.scraper,
    required this.busy,
    required this.onUp,
    required this.onDown,
    required this.onToggle,
    required this.onMode,
  });

  final ScraperInfo scraper;
  final bool busy;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onToggle;
  final VoidCallback onMode;

  /// What the scraper serves, where it runs and its state, on one line.
  String get _facts => [
    if (!scraper.enabled) 'Désactivé',
    if (scraper.types.length == 2)
      'Films et séries'
    else
      scraper.types.contains('tv') ? 'Séries' : 'Films',
    scraper.mode == ScraperMode.server ? 'Sur le serveur' : 'Sur l’appareil',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final logo = layout.size(44, tv: 72);
    final gap = SizedBox(width: layout.size(6, tv: 14));
    final name = scraper.name;
    final onServer = scraper.mode == ScraperMode.server;

    final actions = <Widget>[
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
        icon: onServer ? Icons.cloud_outlined : Icons.smartphone_rounded,
        label: onServer ? 'Exécuter sur l’appareil : $name' : 'Exécuter sur le serveur : $name',
        onPressed: busy ? null : onMode,
      ),
      VxIconAction(
        dense: true,
        icon: scraper.enabled ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
        label: scraper.enabled ? 'Désactiver : $name' : 'Activer : $name',
        active: scraper.enabled,
        onPressed: busy ? null : onToggle,
      ),
    ];

    return VxCard(
      padding: EdgeInsets.symmetric(horizontal: layout.size(14, tv: 24), vertical: layout.size(12, tv: 18)),
      child: Opacity(
        opacity: scraper.enabled ? 1 : 0.6,
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
                    child: scraper.logo == null
                        ? const _LogoFallback()
                        : NetImage(url: scraper.logo, fit: BoxFit.contain, fallback: const _LogoFallback()),
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
                            if (scraper.version.isNotEmpty)
                              TextSpan(
                                text: '  v${scraper.version}',
                                style: VxText.body(12 * s, color: VxColors.textSecondary),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(15 * s, weight: FontWeight.w600),
                      ),
                      if (scraper.description != null) ...[
                        SizedBox(height: layout.size(2, tv: 4)),
                        Text(
                          scraper.description!,
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
            SizedBox(height: layout.size(8, tv: 12)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final (i, action) in actions.indexed) ...[if (i > 0) gap, action],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: VxColors.surfaceHigh,
    child: Icon(Icons.extension_rounded, color: VxColors.textSecondary),
  );
}
