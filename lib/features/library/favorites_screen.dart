import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import '../search/filter_bar.dart';
import '../tv/channel_row.dart';
import '../tv/channel_search.dart';
import '../tv/models.dart';
import 'actions.dart';
import 'library.dart';

/// Type filter of « Favoris ».
enum FavoriteKind {
  all('Tout'),
  movie('Films'),
  tv('Séries'),
  episode('Épisodes'),
  channel('Chaînes TV');

  const FavoriteKind(this.label);

  final String label;

  bool accepts(ProfileItem item) => this == FavoriteKind.all || item.type == name;
}

/// A favorite episode, with its show when the catalog gave it.
typedef FavoriteEpisode = ({ProfileItem item, int showId, MediaItem? show});

/// « Favoris »: what the active profile loves (❤): movies, TV shows, episodes and live channels,
/// synced between devices, most recently added first. Separate from « Ma liste » (to watch later).
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  FavoriteKind _kind = FavoriteKind.all;

  /// Titles already read (show of an episode, logo, rating), kept while the list changes.
  final _known = <TitleRef, MediaItem>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Title, or show then episode name, matching the typed text (case and accents ignored).
  bool _matches(String text) => _query.isEmpty || fold(text).contains(fold(_query));

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final library = ref.watch(libraryProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VxPageHeader(
            title: 'Favoris',
            search: VxSearchField(
              controller: _searchController,
              hintText: 'Films, séries, épisodes, chaînes…',
              fontSize: layout.size(16, tv: 24),
              onChanged: (value) => setState(() => _query = value.trim()),
              onClear: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
            filters: FilterBar(
              child: FilterBar.chips(layout, [
                for (final kind in FavoriteKind.values)
                  FilterChipButton(
                    label: kind.label,
                    selected: _kind == kind,
                    onPressed: () => setState(() => _kind = kind),
                  ),
              ]),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: library,
              onRetry: () => ref.invalidate(libraryProvider),
              data: (state) => _content(context, state.liked),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, List<ProfileItem> liked) {
    final layout = Layout.of(context);

    // Every title and every episode's show in one request (logo, rating, show name): never one
    // per card.
    final refs = <TitleRef>{
      for (final item in liked)
        if (item.tmdbTitle case final t?) (type: t.type, id: t.id),
    };
    final batch = ref.watch(titlesByIdProvider(titlesKey(refs)));
    _known.addAll(batch.value ?? const {});
    // First visit: the cards come with their logo and show, not before.
    if (_known.isEmpty && refs.isNotEmpty && batch.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final shown = liked.where(_kind.accepts).toList();
    final titles = <String, List<MediaItem>>{'movie': [], 'tv': []};
    final episodes = <FavoriteEpisode>[];
    final channels = <TvChannel>[];
    for (final item in shown) {
      final ref = item.tmdbTitle;
      switch (item.type) {
        case 'movie' || 'tv' when ref != null:
          final known = _known[(type: ref.type, id: ref.id)];
          if (!_matches(item.title)) continue;
          titles[item.type]!.add(
            MediaItem(
              id: ref.id,
              type: ref.type,
              title: item.title,
              year: item.year ?? known?.year,
              voteAverage: known?.voteAverage ?? 0,
              posterUrl: item.posterUrl ?? known?.posterUrl,
              backdropUrl: item.backdropUrl ?? known?.backdropUrl,
              logoUrl: known?.logoUrl,
              logoAspectRatio: known?.logoAspectRatio,
              summary: known?.summary,
            ),
          );
        case 'episode' when ref != null:
          final show = _known[(type: ref.type, id: ref.id)];
          if (!_matches('${show?.title ?? ''} ${item.title}')) continue;
          episodes.add((item: item, showId: ref.id, show: show));
        case 'channel':
          final channel = item.asChannel;
          if (channel != null && _matches(item.title)) channels.add(channel);
      }
    }

    final movies = titles['movie']!;
    final shows = titles['tv']!;
    if (movies.isEmpty && shows.isEmpty && episodes.isEmpty && channels.isEmpty) {
      final none = liked.isEmpty;
      return EmptyState(
        icon: Icons.favorite_border_rounded,
        title: none ? 'Aucun favori' : 'Aucun résultat',
        message: none
            ? 'Ajoutez des films, des séries, des épisodes et des chaînes TV avec ♥ pour les retrouver ici, '
                  'sur tous vos écrans.'
            : 'Aucun favori ne correspond à votre recherche ou à ce filtre.',
      );
    }

    final Widget body = switch (_kind) {
      // One type: everything of it, in a grid.
      FavoriteKind.movie => PosterGrid(items: movies, alwaysScrollable: true, padding: pageContentPadding(context)),
      FavoriteKind.tv => PosterGrid(items: shows, alwaysScrollable: true, padding: pageContentPadding(context)),
      FavoriteKind.episode => _EpisodeGrid(episodes: episodes),
      FavoriteKind.channel => _ChannelGrid(channels: channels),
      // "Tout": a row per type.
      FavoriteKind.all => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: layout.isLarge ? layout.tv(16) : 0, bottom: pageBottomPadding(context)),
        children: [
          for (final (i, row) in [
            if (movies.isNotEmpty) PosterRow(title: 'Films', items: movies),
            if (shows.isNotEmpty) PosterRow(title: 'Séries', items: shows),
            if (episodes.isNotEmpty) _EpisodeRow(episodes: episodes),
            if (channels.isNotEmpty) ChannelRow(channels: channels),
          ].indexed) ...[if (i > 0) SizedBox(height: layout.sectionGap), row],
        ],
      ),
    };

    return RefreshIndicator(onRefresh: () => ref.read(libraryProvider.notifier).refresh(), child: body);
  }
}

/// Lower case, without accents: « Équipe » matches « equipe ».
String fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c');

/// Width of an episode card (16:9 still).
double _episodeWidth(Layout layout) => layout.isLarge ? layout.tv(384) : 220;

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episodes});

  final List<FavoriteEpisode> episodes;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final width = _episodeWidth(layout);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Épisodes'),
        FocusTraversalGroup(
          child: SizedBox(
            height: _EpisodeCard.heightOf(width) + (layout.isLarge ? layout.tv(32) : 0),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.isLarge ? layout.tv(16) : 0),
              itemCount: episodes.length,
              separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
              itemBuilder: (_, i) => _EpisodeCard(episode: episodes[i], width: width),
            ),
          ),
        ),
      ],
    );
  }
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.episodes});

  final List<FavoriteEpisode> episodes;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final width = _episodeWidth(layout);
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pageContentPadding(context),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: width + layout.cardGap,
        mainAxisExtent: _EpisodeCard.heightOf(width),
        crossAxisSpacing: layout.cardGap,
        mainAxisSpacing: layout.cardGap,
      ),
      itemCount: episodes.length,
      itemBuilder: (_, i) => LayoutBuilder(
        builder: (_, c) => _EpisodeCard(episode: episodes[i], width: c.maxWidth),
      ),
    );
  }
}

class _ChannelGrid extends ConsumerWidget {
  const _ChannelGrid({required this.channels});

  final List<TvChannel> channels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final tile = layout.isLarge ? layout.tv(140).clamp(96, 160).toDouble() : 96.0;
    final gap = layout.isLarge ? layout.tv(20) : 10.0;
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pageContentPadding(context),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: tile + gap,
        mainAxisExtent: tile + 52,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
      ),
      itemCount: channels.length,
      itemBuilder: (context, i) => Align(
        alignment: Alignment.topCenter,
        child: ChannelTile(channel: channels[i], size: tile, onTap: () => playLiveChannel(context, ref, channels[i])),
      ),
    );
  }
}

/// A favorite episode: its still, the show and « S1 · É3 », its name. A press opens the show; a
/// long press (or the menu key) removes it from « Favoris ».
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.episode, required this.width});

  final FavoriteEpisode episode;
  final double width;

  /// Still (16:9) and two lines of text.
  static double heightOf(double width) => width * 9 / 16 + 58;

  @override
  Widget build(BuildContext context) {
    final item = episode.item;
    final showName = episode.show?.title;
    final numbers = 'S${item.seasonNumber ?? 0} · É${item.episodeNumber ?? 0}';
    final image = item.posterUrl ?? episode.show?.backdropUrl ?? item.backdropUrl;
    final show =
        episode.show ??
        MediaItem(id: episode.showId, type: MediaType.tv, title: showName ?? '', backdropUrl: item.backdropUrl);

    return VxFocusable(
      borderRadius: 12,
      semanticLabel: [?showName, numbers, item.title].join(', '),
      onPressed: () => context.push(titlePath(MediaType.tv, episode.showId)),
      onLongPress: () => toggleEpisodeLiked(
        context,
        show,
        Episode(
          id: 0,
          seasonNumber: item.seasonNumber ?? 0,
          number: item.episodeNumber ?? 0,
          name: item.title,
          stillUrl: item.posterUrl,
        ),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: image == null
                    ? const ColoredBox(
                        color: VxColors.surface,
                        child: Icon(Icons.movie_outlined, color: VxColors.textMuted),
                      )
                    : NetImage(url: image, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showName == null ? numbers : '$showName · $numbers',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VxText.body(12, color: VxColors.textMuted),
            ),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VxText.body(14, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
