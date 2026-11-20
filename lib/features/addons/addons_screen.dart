import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/card.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../playback/player_screen.dart' show sourceProvidersProvider;
import 'scraper_models.dart';
import 'scrapers.dart';

/// « Plug-ins » (« Paramètres » → « Plug-ins »), façon Nuvio (`docs/scrapers.md`): the person adds
/// the address of a **repository** (an add-on: a `manifest.json` somebody hosts). Its scrapers give
/// sources to the player's sources panel, never rows or titles (the catalog stays TMDb's).
///
/// The page lists the **add-ons only, never their scrapers** (demande du développeur): each one
/// can be turned on or off, moved up or down (the sources panel follows this order), read again or
/// removed. Its execution mode is declared in the manifest and only shown.
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

  /// The repository being read again or removed: those two buttons wait for the answer.
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

  /// Runs [action] for the repository [busy] names, then refreshes; an error is shown as an alert.
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

  /// A change kept at once (on / off, order). Its buttons never wait: with a remote, the focus
  /// stays on the button pressed (a button that waits can't hold the focus).
  Future<void> _change(Future<void> Function() action) async {
    await action();
    if (mounted) _refreshSources();
  }

  Future<void> _removeRepo(ScraperRepo repo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer le dépôt'),
        content: Text(
          '« ${repo.name} » ne proposera plus de sources. '
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
          'Ajoutez l’adresse d’un dépôt : il apporte des sources au lecteur. Désactivez un dépôt pour ne '
          'plus voir ses sources sans le retirer ; le choix des sources suit l’ordre des dépôts. '
          'Vixeo n’en fournit aucun, vous êtes responsable des dépôts que vous ajoutez.',
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
                final gap = SizedBox(height: layout.listGap);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, repo) in all.indexed) ...[
                      if (i > 0) gap,
                      _AddonCard(
                        // The card moves with its repository: the focus stays on the button pressed.
                        key: ValueKey(repo.id),
                        repo: repo,
                        busy: _busy == repo.id,
                        onToggle: (on) => _change(() => _repos.setEnabled(repo.id, on)),
                        onUp: i == 0 ? null : () => _change(() => _repos.move(repo.id, i - 1)),
                        onDown: i == all.length - 1 ? null : () => _change(() => _repos.move(repo.id, i + 1)),
                        onRefresh: () => _run(repo.id, () => _repos.refresh(repo.id), done: 'Dépôt mis à jour'),
                        onRemove: () => _removeRepo(repo),
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

/// One add-on: its name, address and version, a switch to turn it on or off, then
/// « monter », « descendre » (buttons, not drag and drop: they work with a TV remote), « mettre à
/// jour » and « retirer ». Its scrapers are not listed.
class _AddonCard extends StatelessWidget {
  const _AddonCard({
    super.key,
    required this.repo,
    required this.busy,
    required this.onToggle,
    required this.onUp,
    required this.onDown,
    required this.onRefresh,
    required this.onRemove,
  });

  final ScraperRepo repo;

  /// Read again or removed right now.
  final bool busy;
  final ValueChanged<bool> onToggle;

  /// Null: already first / last.
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final name = repo.name;
    final on = repo.enabled;
    final facts = [repo.host, if (repo.version != null) 'v${repo.version}'].join(' · ');
    final gap = SizedBox(width: layout.size(6, tv: 14));

    Widget step(IconData icon, String label, VoidCallback? onPressed) => Opacity(
      opacity: onPressed == null ? 0.3 : 1,
      child: VxIconAction(dense: true, icon: icon, label: label, onPressed: onPressed),
    );

    return VxCard(
      padding: EdgeInsets.symmetric(horizontal: layout.size(14, tv: 24), vertical: layout.size(12, tv: 18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The whole top of the card is the switch (remote: OK turns it on or off).
          Semantics(
            toggled: on,
            child: VxFocusable(
              borderRadius: 12 * s,
              focusScale: 1.02,
              semanticLabel: '$name, ${on ? 'activé' : 'désactivé'}',
              onPressed: () => onToggle(!on),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VxText.body(
                              16 * s,
                              weight: FontWeight.w700,
                              color: on ? VxColors.text : VxColors.textSecondary,
                            ),
                          ),
                          SizedBox(height: layout.size(2, tv: 4)),
                          Text(
                            facts,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: VxText.body(12 * s, color: VxColors.textSecondary),
                          ),
                          if (repo.description != null) ...[
                            SizedBox(height: layout.size(4, tv: 6)),
                            Text(
                              repo.description!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: VxText.body(13 * s, color: on ? VxColors.textSoft : VxColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: 12 * s),
                    // The focusable above handles taps and the remote: the switch only shows the state.
                    IgnorePointer(
                      child: ExcludeFocus(
                        child: Transform.scale(
                          scale: s,
                          child: Switch(value: on, onChanged: (_) {}, activeThumbColor: VxColors.accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: layout.size(8, tv: 12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              step(Icons.arrow_upward_rounded, 'Monter : $name', onUp),
              gap,
              step(Icons.arrow_downward_rounded, 'Descendre : $name', onDown),
              gap,
              VxIconAction(
                dense: true,
                icon: Icons.sync_rounded,
                label: 'Mettre à jour le dépôt : $name',
                onPressed: busy ? null : onRefresh,
              ),
              gap,
              VxIconAction(
                dense: true,
                icon: Icons.delete_outline_rounded,
                label: 'Retirer le dépôt : $name',
                onPressed: busy ? null : onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
