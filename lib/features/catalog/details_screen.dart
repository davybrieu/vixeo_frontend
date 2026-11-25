import 'dart:math' show max;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/menu.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/focus_navigation.dart';
import '../auth/session.dart';
import '../library/actions.dart';
import '../network/actions.dart' show recommendToFriend;
import '../network/title_social.dart';
import '../notifications/inbox.dart' show socialAvailable;
import '../profiles/no_spoiler.dart';
import '../ratings/rating_view.dart';
import '../ratings/ratings_sheet.dart';
import '../search/filter_bar.dart';
import '../tmdb/rating_buttons.dart';
import '../tmdb/tmdb.dart';
import 'artwork.dart';
import 'artwork_screen.dart';
import 'catalog_repository.dart';
import 'list_screen.dart';
import 'description_screen.dart';
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

/// « Ajouter à une liste » (« À voir » first) / J'aime ❤ / Vu / Noter / Envoyer à un ami: the same round
/// icon-only button for each action. Each click confirms with an alert (« Ajouté à « À voir » »…).
/// No « Bande-annonce » (the « Bandes-annonces » row, developer's request, 25/11/2026) nor images
/// (the « ⋮ » at the top right).
class _Actions extends ConsumerWidget {
  const _Actions({required this.title});

  final TitleDetails title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final item = title.asItem;
    final social = socialAvailable(ref.watch(sessionProvider)) && !DeviceInfo.isTv;
    return Wrap(
      spacing: layout.isLarge ? layout.tv(20) : 14,
      runSpacing: 12,
      children: [
        FavoriteButton(item: item),
        LikedButton(item: item),
        if (title.type == MediaType.movie) WatchedButton(item: item),
        if (ref.watch(canRateProvider)) RateTitleButton(item: item),
        // The social network (not on a TV): send it to a friend.
        if (social)
          VxIconAction(
            icon: Icons.send_outlined,
            label: 'Envoyer à un ami',
            onPressed: () => recommendToFriend(
              context,
              (type: 'title', id: '${title.type.name}:${title.id}', label: title.title),
            ),
          ),
      ],
    );
  }
}

/// « ⋮ » at the top right of a title page (developer's request, 25/11/2026, as on the profile
/// page): a drop-down to change the images this profile sees for the title, each opening its tab
/// of « Affiches, arrière-plans, logos ». Nothing for a guest.
class _TitleMenuButton extends ConsumerWidget {
  const _TitleMenuButton({required this.title});

  final TitleDetails title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider.select((s) => s.profile == null))) return const SizedBox.shrink();
    return Builder(
      builder: (anchor) => VxIconAction(
        icon: Icons.more_vert_rounded,
        label: 'Plus d’options',
        dense: true,
        onPressed: () => showVxMenu(
          anchor,
          label: 'Personnaliser la fiche',
          items: [
            for (final (kind, icon, label) in [
              (ArtworkKind.poster, Icons.image_outlined, 'Changer l’affiche'),
              (ArtworkKind.backdrop, Icons.wallpaper_rounded, 'Changer l’arrière-plan'),
              (ArtworkKind.logo, Icons.title_rounded, 'Changer le logo'),
            ])
              vxMenuItem(icon, label, () => anchor.push(ArtworkScreen.location(title.type, title.id, kind: kind))),
          ],
        ),
      ),
    );
  }
}

/// « Bandes-annonces » (developer's request, 25/11/2026: a row like the filmography, instead of a
/// button): every trailer and teaser of the title, the best first; a card each, YouTube's still with
/// a play mark, « Teaser » on a teaser, the name under it. A press opens it on YouTube.
class _TrailersRow extends StatelessWidget {
  const _TrailersRow({required this.trailers});

  final List<Trailer> trailers;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final width = _TrailerCard.widthOf(layout);
    // Room for the focus zoom on TV.
    final vPad = layout.isLarge ? layout.tv(16) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Bandes-annonces'),
        FocusTraversalGroup(
          policy: vxTraversalPolicy,
          child: SizedBox(
            height: _TrailerCard.heightOf(context) + vPad * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: vPad),
              itemCount: trailers.length,
              separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
              itemBuilder: (_, i) => SizedBox(width: width, child: _TrailerCard(trailer: trailers[i])),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrailerCard extends StatelessWidget {
  const _TrailerCard({required this.trailer});

  final Trailer trailer;

  static double widthOf(Layout layout) => layout.isLarge ? layout.tv(440) : (layout.isPhone ? 240.0 : 280.0);

  /// The 16:9 still and two lines of name.
  static double heightOf(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.size(14, tv: 22);
    final lines = MediaQuery.textScalerOf(context).scale(size) * 1.35 * 2;
    return widthOf(layout) * 9 / 16 + layout.space(VxSpace.xs) + lines;
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final radius = layout.size(12, tv: 18);
    final name = trailer.name?.trim();
    final play = layout.size(44, tv: 72);
    return VxFocusable(
      borderRadius: radius,
      semanticLabel: [trailer.kind, if (name != null && name.isNotEmpty) name].join(' : '),
      onPressed: () => _openTrailer(context, trailer),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(url: trailer.thumbnailUrl, seed: trailer.url.hashCode),
                    Center(
                      child: Container(
                        width: play,
                        height: play,
                        decoration: const BoxDecoration(color: Color(0xB3070A08), shape: BoxShape.circle),
                        child: Icon(Icons.play_arrow_rounded, color: VxColors.text, size: play * 0.6),
                      ),
                    ),
                    if (trailer.teaser)
                      Positioned(
                        left: layout.space(VxSpace.xs),
                        top: layout.space(VxSpace.xs),
                        child: VxBadge('Teaser', fontSize: layout.size(12, tv: 18)),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: layout.space(VxSpace.xs)),
            Text(
              name == null || name.isEmpty ? trailer.kind : name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: VxText.body(layout.size(14, tv: 22), weight: FontWeight.w600, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Distribution » (the actors, their characters) or « Équipe technique » (everyone else, their
/// jobs in French: « Réalisation, Scénario »), two rows (developer's request, 25/11/2026), 20
/// people each; « Voir tout » opens everyone.
class _PeopleRow extends StatelessWidget {
  const _PeopleRow({required this.title, required this.crew});

  final TitleDetails title;
  final bool crew;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final people = crew ? title.crew : title.cast;
    final heading = crew ? 'Équipe technique' : 'Distribution';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          heading,
          onSeeAll: () => context.push(CreditsScreen.location(title.type, title.id, crew: crew)),
        ),
        FocusTraversalGroup(
          policy: vxTraversalPolicy,
          child: SizedBox(
            height: PersonCard.heightOf(layout) + (layout.isLarge ? layout.tv(32) : 0),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              // Room for the focus zoom on TV.
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.isLarge ? layout.tv(16) : 0),
              itemCount: people.length,
              separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
              itemBuilder: (_, i) => PersonCard(person: people[i], role: people[i].role),
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
    // The profile's reviews of the season's episodes (« Ma note »), for a signed-in profile.
    final canRate = ref.watch(canRateProvider);
    final myRatings = canRate
        ? ref.watch(seasonRatingsProvider((widget.title.id, _season))).value ?? const <int, MyRating>{}
        : const <int, MyRating>{};
    // Room for the focus zoom on TV.
    final vPad = layout.isLarge ? layout.tv(16) : 0.0;
    final rowHeight = _EpisodeCard.heightOf(context) + vPad * 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Épisodes'),
        FocusTraversalGroup(
          policy: vxTraversalPolicy,
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
              policy: vxTraversalPolicy,
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
                    myRating: myRatings[e.number],
                    onPressed: () => _play(context, widget.title, season: _season, episode: e.number),
                    // On the image, top right: the star that rates the episode.
                    rateButton: canRate
                        ? RateEpisodeButton(
                            target: RatingTarget.episode(widget.title.id, _season, e.number),
                            showName: widget.title.title,
                            episode: e,
                            value: myRatings[e.number],
                            imageUrl: widget.title.backdropUrl,
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

/// An episode in the row: a large 16:9 image with the "Épisode 3" badge (then « Ma note : 8/10 »)
/// at the top left, the star that rates it at the top right ([rateButton]) and, at the bottom of
/// the image over a dark gradient, the name, the overview (2 lines at most) and, on the last line,
/// the runtime and just to its right the episode's rating with its site's logo (IMDb's, else
/// TMDb's) on the left, the air date on the right. A tap on the rating, or a long press / the menu
/// key on the card, shows both ratings with their votes (« Notes »). Pressing the card plays the
/// episode. No spoil: no runtime, date nor rating.
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.noSpoiler,
    required this.onPressed,
    this.myRating,
    this.rateButton,
  });

  final Episode episode;
  final bool noSpoiler;
  final VoidCallback onPressed;

  /// The profile's review (« Ma note : 8/10 » next to the badge), null when not rated.
  final MyRating? myRating;
  final Widget? rateButton;

  /// Lines of the overview, at most: the image stays visible above the texts.
  static const overviewLines = 2;

  static double _scaleOf(Layout layout) => layout.isLarge ? layout.scale * 2 : 1.0;

  static double widthOf(Layout layout) => layout.isLarge ? layout.tv(520) : (layout.isPhone ? 300.0 : 340.0);

  static double _insetOf(double s) => 8 * s;

  // Line heights follow the text size chosen in the system settings, so the card never overflows.
  static double _titleHeight(BuildContext context, double s) => MediaQuery.textScalerOf(context).scale(15 * s) * 1.3;
  static double _overviewHeight(BuildContext context, double s) =>
      MediaQuery.textScalerOf(context).scale(13 * s) * 1.4 * overviewLines;
  static double _factsHeight(BuildContext context, double s) => MediaQuery.textScalerOf(context).scale(12 * s) * 1.6;
  static double _badgeHeight(BuildContext context, double s) =>
      MediaQuery.textScalerOf(context).scale(12 * s) * 1.3 + 6 * s;

  /// Height of a card: the row is a horizontal list, which needs it before building its cards.
  /// 16:9, taller only if the badges and the texts don't fit (large system text size).
  static double heightOf(BuildContext context) {
    final layout = Layout.of(context);
    final s = _scaleOf(layout);
    final inset = _insetOf(s);
    // Top: the badge and the rating star; bottom: the texts.
    final top = inset + max(_badgeHeight(context, s), VxIconAction.sizeOf(layout, dense: true)) + 8 * s;
    final texts =
        _titleHeight(context, s) + 4 * s + _overviewHeight(context, s) + 6 * s + _factsHeight(context, s) + 10 * s;
    return max(widthOf(layout) * 9 / 16, top + texts);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = _scaleOf(layout);
    final e = episode;
    final width = widthOf(layout);
    final radius = VxRadius.poster * s;
    final inset = _insetOf(s);
    final caption = VxText.body(12 * s, color: VxColors.textSoft, height: 1.2);
    final image = NetImage(url: e.stillUrl, seed: e.id);
    final overview = e.overview?.trim() ?? '';
    final rating = noSpoiler ? null : e.ratings.shown;
    final showFacts = !noSpoiler && (e.runtime != null || rating != null || e.airDate != null);
    // IMDb and TMDb only: the other sites don't rate episodes.
    void showRatings() => showAllRatings(context, ratings: e.ratings, name: 'Épisode ${e.number} · ${e.name}');

    return SizedBox(
      width: width,
      child: Stack(
        // The focus ring and zoom of the card go past its edges.
        clipBehavior: Clip.none,
        children: [
          VxFocusable(
            borderRadius: radius,
            focusScale: 1.03,
            semanticLabel: [
              'Épisode ${e.number}, ${e.name}',
              if (rating != null) 'note ${rating.$1.label} ${formatRating(rating.$2.value)} sur 10',
            ].join(', '),
            onPressed: onPressed,
            onLongPress: rating == null ? null : showRatings,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: SizedBox(
                width: width,
                height: heightOf(context),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    noSpoiler
                        ? ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: image)
                        : image,
                    // Top left: "Épisode 3", then « Ma note : 8/10 » (the star is on the right).
                    Positioned(
                      left: inset,
                      top: inset,
                      right: inset + VxIconAction.sizeOf(layout, dense: true) + 6 * s,
                      child: Wrap(
                        spacing: 6 * s,
                        runSpacing: 4 * s,
                        children: [
                          _ImageBadge('Épisode ${e.number}', scale: s),
                          if (myRating != null)
                            _ImageBadge('Ma note : ${formatScore(myRating!.value)}/10', scale: s, accent: true),
                        ],
                      ),
                    ),
                    // Bottom: the texts, over a gradient that darkens the image under them.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00070A08), Color(0xB8070A08), Color(0xEB070A08)],
                            stops: [0, 0.35, 1],
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(12 * s, 32 * s, 12 * s, 10 * s),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _episodeSpoiler(
                                Text(
                                  e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: VxText.body(15 * s, weight: FontWeight.w600, height: 1.3).copyWith(
                                    shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)],
                                  ),
                                ),
                                noSpoiler,
                              ),
                              if (overview.isNotEmpty) ...[
                                SizedBox(height: 4 * s),
                                _episodeSpoiler(
                                  Text(
                                    overview,
                                    maxLines: overviewLines,
                                    overflow: TextOverflow.ellipsis,
                                    style: VxText.body(13 * s, color: VxColors.textSoft, height: 1.4),
                                  ),
                                  noSpoiler,
                                ),
                              ],
                              if (showFacts) ...[
                                SizedBox(height: 6 * s),
                                SizedBox(
                                  height: _factsHeight(context, s),
                                  child: Row(
                                    children: [
                                      // Left: runtime, then just to its right the episode's rating with its
                                      // site's logo (shrunk rather than cut). A tap on the rating: « Notes ».
                                      Expanded(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (e.runtime != null) Text(formatRuntime(e.runtime), style: caption),
                                              if (e.runtime != null && rating != null) SizedBox(width: 10 * s),
                                              if (rating != null)
                                                GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onTap: showRatings,
                                                  child: ExcludeSemantics(
                                                    child: RatingLabel(
                                                      site: rating.$1,
                                                      value: rating.$2.value,
                                                      fontSize: 12 * s,
                                                      color: VxColors.textSoft,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Right: first broadcast.
                                      if (e.airDate != null) ...[
                                        SizedBox(width: 10 * s),
                                        Text(formatFrenchDate(e.airDate!), maxLines: 1, style: caption),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

/// Label on an episode image ("Épisode 3", « Ma note : 8/10 »): dark, readable on any image.
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
    final list = ListView(
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
                  // IMDb's rating, else TMDb's: a press shows both with their votes.
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!t.ratings.isEmpty) RatingButton(ratings: t.ratings, name: t.title, title: (type: t.type, id: t.id)),
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
                    DescriptionLink(title: t.title, description: t.overview!),
                  ],
                ],
              ),
            ),
          ],
        ),
        ..._lowerSections(context, layout, t),
      ],
    );
    // Back and « ⋮ » stay at the top while the page scrolls under them.
    return Stack(
      children: [
        list,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: VxFloatingBar(actions: [_TitleMenuButton(title: t)]),
        ),
      ],
    );
  }
}

/// Episodes, people and recommendations, a section gap apart (24, TV 36). People and
/// recommendations have « Voir tout » (the round arrow of their title), like the home rows.
List<Widget> _lowerSections(BuildContext context, Layout layout, TitleDetails t) {
  final gap = SizedBox(height: layout.sectionGap);
  return [
    if (t.type == MediaType.tv && t.seasons.isNotEmpty) ...[gap, _Episodes(title: t)],
    if (t.trailers.isNotEmpty) ...[gap, _TrailersRow(trailers: t.trailers)],
    if (t.cast.isNotEmpty) ...[gap, _PeopleRow(title: t, crew: false)],
    if (t.crew.isNotEmpty) ...[gap, _PeopleRow(title: t, crew: true)],
    // What the members say about it: followed members, popular reviews, lists.
    TitleSocialSection(type: t.type, id: t.id, name: t.title),
    if (t.recommended.isNotEmpty) ...[
      gap,
      PosterRow(
        title: 'Vous pourriez aussi aimer',
        items: t.recommended,
        onSeeAll: () => context.push(RecommendationsScreen.location(t.type, t.id)),
      ),
    ],
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
            // Room for « Retour », which stays at the top (below).
            SizedBox(height: layout.tv(64) + _LargeBack.heightOf(layout)),
            Padding(
              // Same left edge as the sections below (« Distribution », rows).
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
                        if (!t.ratings.isEmpty)
                          RatingButton(
                            ratings: t.ratings,
                            name: t.title,
                            title: (type: t.type, id: t.id),
                            fontSize: layout.tv(22),
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
                        child: DescriptionLink(title: t.title, description: t.overview!),
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
            ..._lowerSections(context, layout, t),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: VxFloatingBar(
            leading: const _LargeBack(),
            actions: [_TitleMenuButton(title: t)],
            safeArea: false,
            padding: EdgeInsets.fromLTRB(layout.gutter, layout.tv(64), layout.gutter, 0),
          ),
        ),
      ],
    );
  }
}

/// « Retour » with its word, at the top left of a large title page.
class _LargeBack extends StatelessWidget {
  const _LargeBack();

  static double heightOf(Layout layout) => layout.tv(10) * 2 + layout.tv(19) * 1.4;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return VxFocusable(
      borderRadius: layout.tv(24),
      semanticLabel: 'Retour',
      onPressed: () => context.canPop() ? context.pop() : context.go('/accueil'),
      child: Container(
        height: heightOf(layout),
        padding: EdgeInsets.symmetric(horizontal: layout.tv(18)),
        decoration: BoxDecoration(color: const Color(0x8C070A08), borderRadius: BorderRadius.circular(layout.tv(24))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: layout.tv(24), color: VxColors.textSoft),
            SizedBox(width: layout.tv(8)),
            Text('Retour', style: VxText.body(layout.tv(19), color: VxColors.textSoft)),
          ],
        ),
      ),
    );
  }
}
