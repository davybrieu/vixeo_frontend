import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../library/library.dart';
import 'catalog_repository.dart';
import 'models.dart';
import 'widgets.dart';

/// Movie or TV show page.
class DetailsScreen extends ConsumerWidget {
  const DetailsScreen({super.key, required this.type, required this.id});

  final MediaType type;
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(titleProvider((type, id)));
    final layout = Layout.of(context);

    return Scaffold(
      body: AsyncView(
        value: details,
        onRetry: () => ref.invalidate(titleProvider((type, id))),
        data: (title) => layout.isPhone ? _PhoneDetails(title: title) : _LargeDetails(title: title),
      ),
      // Errors (e.g. "pas disponible sur ce profil") still need a way back.
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      floatingActionButton: details.hasError ? const _BackButton() : null,
    );
  }
}

void _play(BuildContext context) => showVxSnack(
  context,
  'Aucune source disponible pour ce contenu. Ajoutez un serveur Jellyfin, Plex ou Emby pour le regarder.',
);

Future<void> _openTrailer(BuildContext context, Trailer trailer) async {
  final ok = await launchUrl(Uri.parse(trailer.url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showVxSnack(context, 'Impossible d’ouvrir la bande-annonce.');
}

String _ageLabel(int age) => age == 0 ? 'Tous publics' : '$age+';

List<String> _meta(TitleDetails t) => [
  if (t.year != null) '${t.year}',
  if (t.type == MediaType.movie && t.runtime != null) formatRuntime(t.runtime),
  if (t.type == MediaType.tv && t.numberOfSeasons > 0) '${t.numberOfSeasons} saison${t.numberOfSeasons > 1 ? 's' : ''}',
];

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: VxFocusable(
        borderRadius: 22,
        semanticLabel: 'Retour',
        onPressed: () => context.canPop() ? context.pop() : context.go('/accueil'),
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: Color(0x99070A08), shape: BoxShape.circle),
          child: const Icon(Icons.arrow_back_rounded, color: VxColors.text),
        ),
      ),
    ),
  );
}

/// Ma liste / Vu / Bande-annonce, wired to the sync API.
class _Actions extends ConsumerWidget {
  const _Actions({required this.title, this.showLabels = true});

  final TitleDetails title;
  final bool showLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = title.asItem;
    final state = ref.watch(libraryProvider).value?.forItem(item);
    final library = ref.read(libraryProvider.notifier);
    final favorite = state?.isFavorite ?? false;
    final watched = state?.isWatched ?? false;

    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        if (context.mounted) showVxSnack(context, done);
      } catch (e) {
        if (context.mounted) showVxSnack(context, '$e');
      }
    }

    return Wrap(
      spacing: showLabels ? 4 : 16,
      runSpacing: 12,
      children: [
        VxIconAction(
          icon: favorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          label: favorite ? 'Dans ma liste' : 'Ma liste',
          active: favorite,
          showLabel: showLabels,
          onPressed: () =>
              run(() => library.setFavorite(item, !favorite), favorite ? 'Retiré de ma liste' : 'Ajouté à ma liste'),
        ),
        if (title.type == MediaType.movie)
          VxIconAction(
            icon: watched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
            label: watched ? 'Vu' : 'Marquer vu',
            active: watched,
            showLabel: showLabels,
            onPressed: () =>
                run(() => library.setWatched(item, !watched), watched ? 'Marqué comme non vu' : 'Marqué comme vu'),
          ),
        if (title.trailer != null)
          VxIconAction(
            icon: Icons.smart_display_outlined,
            label: 'Bande-annonce',
            showLabel: showLabels,
            onPressed: () => _openTrailer(context, title.trailer!),
          ),
      ],
    );
  }
}

/// No playback source yet (Jellyfin / Plex / Emby come later).
class _SourcesSection extends StatelessWidget {
  const _SourcesSection();

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Sources'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.isLarge ? layout.tv(900) : 600),
            child: Container(
              padding: EdgeInsets.all(16 * s),
              decoration: BoxDecoration(
                color: VxColors.surface,
                borderRadius: BorderRadius.circular(14 * s),
                border: Border.all(color: VxColors.surfaceHigh),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40 * s,
                    height: 40 * s,
                    decoration: BoxDecoration(color: VxColors.surfaceHigh, borderRadius: BorderRadius.circular(10 * s)),
                    child: Icon(Icons.dns_outlined, color: VxColors.accent, size: 20 * s),
                  ),
                  SizedBox(width: 14 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aucune source pour l’instant', style: VxText.body(15 * s, weight: FontWeight.w600)),
                        SizedBox(height: 2 * s),
                        Text(
                          'Ajoutez votre serveur Jellyfin, Plex ou Emby pour regarder ce titre.',
                          style: VxText.body(13 * s, color: VxColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.people});

  final List<Person> people;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.isLarge ? layout.tv(120) : 72.0;
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Distribution'),
        SizedBox(
          height: size + 64 * s,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            itemCount: people.length,
            separatorBuilder: (_, _) => SizedBox(width: 16 * s),
            itemBuilder: (_, i) {
              final p = people[i];
              return SizedBox(
                width: size + 8,
                child: Semantics(
                  label: p.role == null ? p.name : '${p.name}, ${p.role}',
                  child: ExcludeSemantics(
                    child: Column(
                      children: [
                        ClipOval(
                          child: SizedBox.square(
                            dimension: size,
                            child: NetImage(
                              url: p.profileUrl,
                              seed: p.id,
                              fallback: Center(child: Text(p.initials, style: VxText.title(size * 0.3))),
                            ),
                          ),
                        ),
                        SizedBox(height: 6 * s),
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: VxText.body(13 * s, weight: FontWeight.w600, height: 1.2),
                        ),
                        if (p.role != null)
                          Text(
                            p.role!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: VxText.body(12 * s, color: VxColors.textSecondary, height: 1.2),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Season picker + episode list.
class _Episodes extends ConsumerStatefulWidget {
  const _Episodes({required this.title});

  final TitleDetails title;

  @override
  ConsumerState<_Episodes> createState() => _EpisodesState();
}

class _EpisodesState extends ConsumerState<_Episodes> {
  late int _season = widget.title.seasons.firstOrNull?.number ?? 1;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    final season = ref.watch(seasonProvider((widget.title.id, _season)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Épisodes'),
        FocusTraversalGroup(
          child: SizedBox(
            height: 44 * s,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              itemCount: widget.title.seasons.length,
              separatorBuilder: (_, _) => SizedBox(width: 8 * s),
              itemBuilder: (_, i) {
                final item = widget.title.seasons[i];
                final selected = item.number == _season;
                return VxFocusable(
                  borderRadius: 22 * s,
                  semanticLabel: item.name,
                  onPressed: () => setState(() => _season = item.number),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16 * s),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? VxColors.accent.withValues(alpha: 0.14) : Colors.transparent,
                      border: selected ? null : Border.all(color: VxColors.lineStrong),
                      borderRadius: BorderRadius.circular(22 * s),
                    ),
                    child: Text(
                      item.number == 0 ? 'Épisodes spéciaux' : 'Saison ${item.number}',
                      style: VxText.body(
                        14 * s,
                        weight: FontWeight.w600,
                        color: selected ? VxColors.accent : VxColors.text,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        SizedBox(height: 14 * s),
        AsyncView(
          value: season,
          onRetry: () => ref.invalidate(seasonProvider((widget.title.id, _season))),
          loading: const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          data: (data) => Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.gutter),
            child: Column(
              children: [
                for (final e in data.episodes)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12 * s),
                    child: VxFocusable(
                      borderRadius: 12 * s,
                      semanticLabel: 'Épisode ${e.number}, ${e.name}',
                      onPressed: () => _play(context),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10 * s),
                            child: SizedBox(
                              width: 136 * s,
                              height: 77 * s,
                              child: NetImage(url: e.stillUrl, seed: e.id),
                            ),
                          ),
                          SizedBox(width: 12 * s),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${e.number}. ${e.name}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: VxText.body(14 * s, weight: FontWeight.w600, height: 1.3),
                                ),
                                if (e.runtime != null)
                                  Text(
                                    formatRuntime(e.runtime),
                                    style: VxText.body(12 * s, color: VxColors.textSecondary),
                                  ),
                                if (e.overview != null && !layout.isPhone)
                                  Text(
                                    e.overview!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: VxText.body(13 * s, color: VxColors.textSoft),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Phone ─────────────────────────────

class _PhoneDetails extends StatefulWidget {
  const _PhoneDetails({required this.title});

  final TitleDetails title;

  @override
  State<_PhoneDetails> createState() => _PhoneDetailsState();
}

class _PhoneDetailsState extends State<_PhoneDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SizedBox(
          height: 340,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(url: t.asItem.backdrop('w1280'), seed: t.id),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x73070A08), Colors.transparent, Color(0xB3070A08), VxColors.background],
                    stops: [0, 0.3, 0.75, 1],
                  ),
                ),
              ),
              const Positioned(left: 0, top: 0, child: _BackButton()),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: VxText.title(32, weight: FontWeight.w800)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (t.voteAverage > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: VxColors.accent, size: 17),
                          const SizedBox(width: 3),
                          Text(formatRating(t.voteAverage), style: VxText.body(14, weight: FontWeight.w600)),
                        ],
                      ),
                    for (final m in _meta(t)) Text(m, style: VxText.body(14, color: VxColors.textSoft)),
                    if (t.ageRating != null) VxBadge(_ageLabel(t.ageRating!), outlined: true),
                  ],
                ),
                if (t.genres.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(t.genres.map((g) => g.name).join(' · '), style: VxText.body(14, color: VxColors.textSecondary)),
                ],
                const SizedBox(height: 18),
                VxButton(
                  label: 'Lecture',
                  icon: Icons.play_arrow_rounded,
                  expand: true,
                  onPressed: () => _play(context),
                ),
                const SizedBox(height: 16),
                _Actions(title: t),
                if (t.overview != null) ...[
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      t.overview!,
                      maxLines: _expanded ? null : 4,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: VxText.body(15, color: VxColors.textSoft, height: 1.55),
                    ),
                  ),
                ],
                if (t.crew.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${t.type == MediaType.movie ? 'Réalisation' : 'Création'} : ${t.crew.map((p) => p.name).join(', ')}',
                    style: VxText.body(13, color: VxColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        ..._lowerSections(t, top: -40),
      ],
    );
  }
}

List<Widget> _lowerSections(TitleDetails t, {double top = 0}) => [
  Transform.translate(offset: Offset(0, top), child: const _SourcesSection()),
  if (t.type == MediaType.tv && t.seasons.isNotEmpty) ...[const SizedBox(height: 8), _Episodes(title: t)],
  if (t.cast.isNotEmpty) ...[const SizedBox(height: 16), _CastRow(people: t.cast)],
  if (t.recommended.isNotEmpty) ...[
    const SizedBox(height: 16),
    PosterRow(title: 'Vous pourriez aussi aimer', items: t.recommended),
  ],
];

// ───────────────────────────── TV / large ─────────────────────────────

class _LargeDetails extends StatelessWidget {
  const _LargeDetails({required this.title});

  final TitleDetails title;

  @override
  Widget build(BuildContext context) {
    final t = title;
    final layout = Layout.of(context);
    final size = MediaQuery.sizeOf(context);

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(url: t.asItem.backdrop('original'), seed: t.id),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [VxColors.background, Color(0xE6070A08), Color(0x40070A08), Color(0x1A070A08)],
                    stops: [0, 0.38, 0.7, 1],
                  ),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, VxColors.background],
                    stops: [0.55, 1],
                  ),
                ),
              ),
            ],
          ),
        ),
        ListView(
          padding: EdgeInsets.only(bottom: layout.tv(80)),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, layout.tv(64), layout.gutter, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: VxFocusable(
                  borderRadius: layout.tv(24),
                  semanticLabel: 'Retour',
                  onPressed: () => context.canPop() ? context.pop() : context.go('/accueil'),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: layout.tv(18), vertical: layout.tv(10)),
                    decoration: BoxDecoration(
                      color: const Color(0x8C070A08),
                      borderRadius: BorderRadius.circular(layout.tv(24)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_rounded, size: layout.tv(24), color: VxColors.textSoft),
                        SizedBox(width: layout.tv(8)),
                        Text('Retour', style: VxText.body(layout.tv(19), color: VxColors.textSoft)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter + layout.tv(64), layout.tv(60), layout.gutter, layout.tv(48)),
              child: SizedBox(
                width: layout.tv(1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 2, style: VxText.title(layout.tv(100), weight: FontWeight.w800)),
                    SizedBox(height: layout.tv(22)),
                    Wrap(
                      spacing: layout.tv(18),
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (t.voteAverage > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, color: VxColors.accent, size: layout.tv(26)),
                              SizedBox(width: layout.tv(6)),
                              Text(
                                formatRating(t.voteAverage),
                                style: VxText.body(layout.tv(22), weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        for (final m in _meta(t)) Text(m, style: VxText.body(layout.tv(22), color: VxColors.textSoft)),
                        if (t.genres.isNotEmpty)
                          Text(
                            t.genres.map((g) => g.name).join(' · '),
                            style: VxText.body(layout.tv(22), color: VxColors.textSoft),
                          ),
                        if (t.ageRating != null)
                          VxBadge(_ageLabel(t.ageRating!), outlined: true, fontSize: layout.tv(18)),
                      ],
                    ),
                    if (t.overview != null) ...[
                      SizedBox(height: layout.tv(22)),
                      SizedBox(
                        width: layout.tv(820),
                        child: Text(
                          t.overview!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(layout.tv(24), color: VxColors.textSoft),
                        ),
                      ),
                    ],
                    if (t.cast.isNotEmpty || t.crew.isNotEmpty) ...[
                      SizedBox(height: layout.tv(16)),
                      Text(
                        [
                          if (t.cast.isNotEmpty) 'Avec ${t.cast.take(3).map((p) => p.name).join(', ')}',
                          if (t.crew.isNotEmpty)
                            '${t.type == MediaType.movie ? 'Réalisation' : 'Création'} : ${t.crew.first.name}',
                        ].join(' · '),
                        style: VxText.body(layout.tv(20), color: VxColors.textSecondary),
                      ),
                    ],
                    SizedBox(height: layout.tv(36)),
                    Row(
                      children: [
                        VxButton(
                          label: 'Lecture',
                          icon: Icons.play_arrow_rounded,
                          autofocus: true,
                          onPressed: () => _play(context),
                        ),
                        SizedBox(width: layout.tv(24)),
                        _Actions(title: t, showLabels: false),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ..._lowerSections(t),
          ],
        ),
      ],
    );
  }
}
