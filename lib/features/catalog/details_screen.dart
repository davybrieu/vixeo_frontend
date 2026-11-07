import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/expandable_text.dart';
import '../library/actions.dart';
import '../profiles/no_spoiler.dart';
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


void _play(BuildContext context, TitleDetails title, {int? season, int? episode}) {
  final type = title.type == MediaType.movie ? 'movie' : 'tv';
  final path = '/lecture/$type/${title.id}';
  final query = (season != null && episode != null) ? '?saison=$season&episode=$episode' : '';
  context.push('$path$query');
}

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

/// Ma liste / Vu / Bande-annonce: the same round icon-only button for each action.
/// Each click confirms with an alert ("Supprimé de votre liste"…).
class _Actions extends StatelessWidget {
  const _Actions({required this.title});

  final TitleDetails title;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final item = title.asItem;
    return Wrap(
      spacing: layout.isLarge ? layout.tv(20) : 14,
      runSpacing: 12,
      children: [
        FavoriteButton(item: item),
        if (title.type == MediaType.movie) WatchedButton(item: item),
        if (title.trailer != null)
          VxIconAction(
            icon: Icons.smart_display_outlined,
            label: 'Voir la bande-annonce',
            onPressed: () => _openTrailer(context, title.trailer!),
          ),
      ],
    );
  }
}

/// "Créateur et distribution": the director(s) of a movie or creator(s) of a TV show first, on
/// the left, then the cast ("Distribution" alone when TMDb gives no director or creator).
class _PeopleRow extends StatelessWidget {
  const _PeopleRow({required this.title});

  final TitleDetails title;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final crewRole = title.type == MediaType.movie ? 'Réalisation' : 'Création';
    final people = [for (final p in title.crew) (p, crewRole), for (final p in title.cast) (p, p.role)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title.crew.isEmpty ? 'Distribution' : 'Créateur et distribution'),
        FocusTraversalGroup(
          child: SizedBox(
            height: PersonCard.heightOf(layout) + (layout.isLarge ? layout.tv(32) : 0),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              // Room for the focus zoom on TV.
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.isLarge ? layout.tv(16) : 0),
              itemCount: people.length,
              separatorBuilder: (_, _) => SizedBox(width: layout.isLarge ? layout.tv(24) : 8),
              itemBuilder: (_, i) => PersonCard(person: people[i].$1, role: people[i].$2),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _episodeSpoiler(Widget child, bool enabled) => enabled
    ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7), child: child)
    : child;

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
    final noSpoiler = ref.watch(noSpoilerProvider);

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
                      onPressed: () => _play(context, widget.title, season: _season, episode: e.number),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10 * s),
                            child: SizedBox(
                              width: 136 * s,
                              height: 77 * s,
                              child: noSpoiler
                                  ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: NetImage(url: e.stillUrl, seed: e.id))
                                  : NetImage(url: e.stillUrl, seed: e.id),
                            ),
                          ),
                          SizedBox(width: 12 * s),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _episodeSpoiler(
                                  Text(
                                    '${e.number}. ${e.name}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: VxText.body(14 * s, weight: FontWeight.w600, height: 1.3),
                                  ),
                                  noSpoiler,
                                ),
                                Wrap(
                                  spacing: 10 * s,
                                  runSpacing: 2 * s,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (!noSpoiler && e.runtime != null)
                                      Text(
                                        formatRuntime(e.runtime),
                                        style: VxText.body(12 * s, color: VxColors.textSecondary),
                                      ),
                                    if (!noSpoiler && e.voteAverage > 0)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.star_rounded, color: VxColors.accent, size: 14 * s),
                                          SizedBox(width: 3 * s),
                                          Text(
                                            formatRating(e.voteAverage),
                                            style: VxText.body(12 * s, color: VxColors.textSecondary, weight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                if (e.overview != null && e.overview!.trim().isNotEmpty)
                                  _episodeSpoiler(
                                    Text(
                                      e.overview!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: VxText.body(13 * s, color: VxColors.textSoft),
                                    ),
                                    noSpoiler,
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
  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    final logo = TitleLogo.sizeFor(
      t.logoUrl,
      t.logoAspectRatio,
      maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      maxHeight: 96,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Stack(
          children: [
            SizedBox(
              height: 340,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(url: t.background('w1280'), seed: t.id),
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
                ],
              ),
            ),
            Padding(
              // The title overlaps the bottom of the backdrop; a logo sits on it.
              padding: EdgeInsets.fromLTRB(20, logo == null ? 276 : 330 - logo.height, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TitleLogo(
                    name: t.title,
                    logoUrl: t.logoUrl,
                    size: logo,
                    style: VxText.title(32, weight: FontWeight.w800),
                  ),
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
                    Text(
                      t.genres.map((g) => g.name).join(' · '),
                      style: VxText.body(14, color: VxColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 18),
                  VxButton(
                    label: 'Lecture',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    onPressed: () => _play(context, t),
                  ),
                  const SizedBox(height: 16),
                  _Actions(title: t),
                  if (t.overview != null) ...[
                    const SizedBox(height: 16),
                    ExpandableText(text: t.overview!, maxLines: 5),
                  ],
                ],
              ),
            ),
            const Positioned(left: 0, top: 0, child: _BackButton()),
          ],
        ),
        ..._lowerSections(t),
      ],
    );
  }
}

List<Widget> _lowerSections(TitleDetails t) => [
  if (t.type == MediaType.tv && t.seasons.isNotEmpty) ...[const SizedBox(height: 8), _Episodes(title: t)],
  if (t.cast.isNotEmpty || t.crew.isNotEmpty) ...[const SizedBox(height: 16), _PeopleRow(title: t)],
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
              NetImage(url: t.background('original'), seed: t.id),
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
              // Same left edge as the sections below ("Créateur et distribution", rows).
              padding: EdgeInsets.fromLTRB(layout.gutter, layout.tv(60), layout.gutter, layout.tv(48)),
              child: SizedBox(
                width: layout.tv(1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TitleLogo(
                      name: t.title,
                      logoUrl: t.logoUrl,
                      size: TitleLogo.sizeFor(
                        t.logoUrl,
                        t.logoAspectRatio,
                        maxWidth: layout.tv(760),
                        maxHeight: layout.tv(220),
                      ),
                      maxLines: 2,
                      style: VxText.title(layout.tv(100), weight: FontWeight.w800),
                    ),
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
                        child: ExpandableText(text: t.overview!, maxLines: 5),
                      ),
                    ],
                    SizedBox(height: layout.tv(36)),
                    Row(
                      children: [
                        VxButton(
                          label: 'Lecture',
                          icon: Icons.play_arrow_rounded,
                          autofocus: true,
                          onPressed: () => _play(context, t),
                        ),
                        SizedBox(width: layout.tv(24)),
                        _Actions(title: t),
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
