import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/expandable_text.dart';
import '../auth/session.dart';
import '../library/actions.dart';
import '../profiles/no_spoiler.dart';
import '../search/filter_bar.dart';
import '../tmdb/rating_buttons.dart';
import '../tmdb/tmdb.dart';
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

/// Ma liste / Vu / Noter / Bande-annonce: the same round icon-only button for each action.
/// Each click confirms with an alert ("Supprimé de votre liste"…). "Noter" needs a TMDb account.
class _Actions extends ConsumerWidget {
  const _Actions({required this.title});

  final TitleDetails title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final item = title.asItem;
    final guest = ref.watch(sessionProvider.select((s) => s.isGuest));
    return Wrap(
      spacing: layout.isLarge ? layout.tv(20) : 14,
      runSpacing: 12,
      children: [
        if (!guest) FavoriteButton(item: item),
        if (!guest && title.type == MediaType.movie) WatchedButton(item: item),
        if (!guest && ref.watch(canRateProvider)) RateTitleButton(type: title.type, id: title.id, name: title.title),
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
              separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
              itemBuilder: (_, i) => PersonCard(person: people[i].$1, role: people[i].$2),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _episodeSpoiler(Widget child, bool enabled) =>
    enabled ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7), child: child) : child;

/// Season picker + episodes: a horizontal row of large 16:9 cards.
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
    final canRate = ref.watch(canRateProvider);
    final ratings = canRate ? ref.watch(seasonRatingsProvider((widget.title.id, _season))).value ?? const {} : const {};
    // Room for the focus zoom on TV.
    final vPad = layout.isLarge ? layout.tv(16) : 0.0;
    final rowHeight = _EpisodeCard.heightOf(context) + vPad * 2;

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
              separatorBuilder: (_, _) => SizedBox(width: FilterBar.gapOf(layout)),
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
        // Chips, then their content: as under a page header's filters (less the room for the zoom).
        SizedBox(height: layout.space(VxSpace.m) - vPad),
        // The row keeps its height while a season loads: the sections below don't move.
        SizedBox(
          height: rowHeight,
          child: AsyncView(
            value: season,
            onRetry: () => ref.invalidate(seasonProvider((widget.title.id, _season))),
            loading: const Center(child: CircularProgressIndicator()),
            data: (data) => FocusTraversalGroup(
              child: ListView.separated(
                // Another season starts at its first episode.
                key: ValueKey(_season),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: vPad),
                itemCount: data.episodes.length,
                separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
                itemBuilder: (context, i) {
                  final e = data.episodes[i];
                  return _EpisodeCard(
                    episode: e,
                    noSpoiler: noSpoiler,
                    rating: ratings[e.number],
                    onPressed: () => _play(context, widget.title, season: _season, episode: e.number),
                    // On the image, top right: the star that rates the episode (TMDb account).
                    rateButton: canRate
                        ? RateEpisodeButton(
                            target: RatingTarget.episode(widget.title.id, _season, e.number),
                            showName: widget.title.title,
                            episode: e,
                            value: ratings[e.number],
                          )
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An episode in the row: a large 16:9 image with the "Épisode 3" badge, then the name, the
/// overview (3 lines at most) and, on the last line, the runtime and TMDb's rating on the left,
/// the air date on the right. Pressing the card plays the episode.
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.noSpoiler,
    required this.onPressed,
    this.rating,
    this.rateButton,
  });

  final Episode episode;
  final bool noSpoiler;
  final VoidCallback onPressed;

  /// The profile's rating ("Ma note : 8/10" on the image), null when not rated.
  final MyRating? rating;
  final Widget? rateButton;

  static double _scaleOf(Layout layout) => layout.isLarge ? layout.scale * 2 : 1.0;

  static double widthOf(Layout layout) => layout.isLarge ? layout.tv(520) : (layout.isPhone ? 300.0 : 340.0);

  // Line heights follow the text size chosen in the system settings, so the card never overflows.
  static double _titleHeight(BuildContext context, double s) => MediaQuery.textScalerOf(context).scale(15 * s) * 1.3;
  static double _overviewHeight(BuildContext context, double s) =>
      MediaQuery.textScalerOf(context).scale(13 * s) * 1.4 * 3;
  static double _factsHeight(BuildContext context, double s) => MediaQuery.textScalerOf(context).scale(12 * s) * 1.6;

  /// Height of a card: the row is a horizontal list, which needs it before building its cards.
  static double heightOf(BuildContext context) {
    final layout = Layout.of(context);
    final s = _scaleOf(layout);
    return widthOf(layout) * 9 / 16 +
        layout.space(VxSpace.s) +
        _titleHeight(context, s) +
        4 * s +
        _overviewHeight(context, s) +
        8 * s +
        _factsHeight(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = _scaleOf(layout);
    final e = episode;
    final width = widthOf(layout);
    final radius = VxRadius.poster * s;
    final inset = 8 * s;
    final caption = VxText.body(12 * s, color: VxColors.textSecondary, height: 1.2);
    final image = NetImage(url: e.stillUrl, seed: e.id);
    final overview = e.overview?.trim() ?? '';

    return SizedBox(
      width: width,
      child: Stack(
        // The focus ring and zoom of the card go past its edges.
        clipBehavior: Clip.none,
        children: [
          VxFocusable(
            borderRadius: radius,
            focusScale: 1.03,
            semanticLabel: 'Épisode ${e.number}, ${e.name}',
            onPressed: onPressed,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        noSpoiler
                            ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: image)
                            : image,
                        Positioned(left: inset, top: inset, child: _ImageBadge('Épisode ${e.number}', scale: s)),
                        if (rating != null)
                          Positioned(
                            left: inset,
                            bottom: inset,
                            child: _ImageBadge('Ma note : ${formatScore(rating!.value)}/10', scale: s, accent: true),
                          ),
                      ],
                    ),
                  ),
                ),
                // Between an image and its text.
                SizedBox(height: layout.space(VxSpace.s)),
                SizedBox(
                  height: _titleHeight(context, s),
                  child: _episodeSpoiler(
                    Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(15 * s, weight: FontWeight.w600, height: 1.3),
                    ),
                    noSpoiler,
                  ),
                ),
                SizedBox(height: 4 * s),
                // Always 3 lines high: the last line is at the same place on every card.
                SizedBox(
                  height: _overviewHeight(context, s),
                  child: overview.isEmpty
                      ? null
                      : _episodeSpoiler(
                          Text(
                            overview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: VxText.body(13 * s, color: VxColors.textSoft, height: 1.4),
                          ),
                          noSpoiler,
                        ),
                ),
                SizedBox(height: 8 * s),
                SizedBox(
                  height: _factsHeight(context, s),
                  child: Row(
                    children: [
                      // Left: runtime, then TMDb's rating (shrunk rather than cut when the line is full).
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!noSpoiler && e.runtime != null) Text(formatRuntime(e.runtime), style: caption),
                              if (!noSpoiler && e.runtime != null && e.voteAverage > 0) SizedBox(width: 10 * s),
                              if (!noSpoiler && e.voteAverage > 0)
                                TmdbRating(e.voteAverage, fontSize: 12 * s, color: VxColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                      // Right: first broadcast.
                      if (!noSpoiler && e.airDate != null) ...[
                        SizedBox(width: 10 * s),
                        Text(formatFrenchDate(e.airDate!), maxLines: 1, style: caption),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (rateButton != null)
            Positioned(
              right: inset,
              top: inset,
              // Dark disc: the star stays readable on a bright image.
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Color(0xB3070A08), shape: BoxShape.circle),
                child: rateButton,
              ),
            ),
        ],
      ),
    );
  }
}

/// Label on an episode image ("Épisode 3", "Ma note : 8/10"): dark, readable on any image.
class _ImageBadge extends StatelessWidget {
  const _ImageBadge(this.label, {required this.scale, this.accent = false});

  final String label;
  final double scale;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
    decoration: BoxDecoration(color: const Color(0xCC070A08), borderRadius: BorderRadius.circular(6 * scale)),
    child: Text(
      label,
      style: VxText.body(
        12 * scale,
        weight: FontWeight.w600,
        color: accent ? VxColors.accent : VxColors.text,
        height: 1.3,
      ),
    ),
  );
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
    final layout = Layout.of(context);
    return ListView(
      padding: EdgeInsets.only(bottom: pageBottomPadding(context)),
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
              padding: EdgeInsets.fromLTRB(layout.gutter, logo == null ? 276 : 330 - logo.height, layout.gutter, 0),
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
                      if (t.voteAverage > 0) TmdbRating(t.voteAverage),
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
                  const SizedBox(height: VxSpace.m),
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
        ..._lowerSections(layout, t),
      ],
    );
  }
}

/// Episodes, people and recommendations, a section gap apart (24, TV 36).
List<Widget> _lowerSections(Layout layout, TitleDetails t) {
  final gap = SizedBox(height: layout.sectionGap);
  return [
    if (t.type == MediaType.tv && t.seasons.isNotEmpty) ...[gap, _Episodes(title: t)],
    if (t.cast.isNotEmpty || t.crew.isNotEmpty) ...[gap, _PeopleRow(title: t)],
    if (t.recommended.isNotEmpty) ...[gap, PosterRow(title: 'Vous pourriez aussi aimer', items: t.recommended)],
  ];
}

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
          padding: EdgeInsets.only(bottom: pageBottomPadding(context)),
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
              padding: EdgeInsets.fromLTRB(layout.gutter, layout.tv(60), layout.gutter, 0),
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
                        if (t.voteAverage > 0) TmdbRating(t.voteAverage, fontSize: layout.tv(22)),
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
                    SizedBox(height: layout.sectionGap),
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
            ..._lowerSections(layout, t),
          ],
        ),
      ],
    );
  }
}
