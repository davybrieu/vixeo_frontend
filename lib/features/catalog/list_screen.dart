import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';
import '../search/search_screen.dart';
import 'catalog_repository.dart';
import 'models.dart';
import 'widgets.dart';

/// "Voir tout" of a home row: every title of the list (trending movies, popular TV shows…) in a
/// grid that loads the next page when its end comes into view.
class TitleListScreen extends ConsumerWidget {
  const TitleListScreen({super.key, required this.type, required this.list, this.title});

  final MediaType type;

  /// The list of the API: `trending`, `popular`, `top_rated`…
  final String list;

  /// The row's title; without it (address typed by hand), "Films" or "Séries".
  final String? title;

  static String location(MediaType type, String list, String title) =>
      '/liste/${type.name}/$list?titre=${Uri.encodeQueryComponent(title)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heading = (title == null || title!.trim().isEmpty) ? (type == MediaType.movie ? 'Films' : 'Séries') : title!;
    return _SeeAllPage(
      heading: heading,
      content: _PagedTitles(page: (page) => titleListProvider((type, list, page))),
    );
  }
}

/// "Voir tout" of « Vous pourriez aussi aimer » on a title page: every recommendation, page by page.
class RecommendationsScreen extends StatelessWidget {
  const RecommendationsScreen({super.key, required this.type, required this.id});

  final MediaType type;
  final int id;

  static String location(MediaType type, int id) => '/titre/${type.name}/$id/recommandations';

  @override
  Widget build(BuildContext context) => _SeeAllPage(
    heading: 'Vous pourriez aussi aimer',
    content: _PagedTitles(page: (page) => recommendationsProvider((type, id, page))),
  );
}

/// "Voir tout" of the movies or TV shows row on a person page.
class PersonTitlesScreen extends StatelessWidget {
  const PersonTitlesScreen({super.key, required this.id, required this.sort});

  final int id;
  final PersonCreditsType sort;

  static String location(int id, PersonCreditsType sort) =>
      '/personne/$id/${sort == PersonCreditsType.movie ? 'films' : 'series'}';

  @override
  Widget build(BuildContext context) => _SeeAllPage(
    heading: sort == PersonCreditsType.movie ? 'Films' : 'Séries',
    content: _PagedTitles(
      page: (page) => personCreditsProvider((id, sort, page)),
      empty: const EmptyState(icon: Icons.movie_filter_outlined, title: 'Aucun titre disponible pour ce profil'),
    ),
  );
}

/// « Voir tout » of « Distribution » (the whole cast) or « Équipe technique » (everyone else, their
/// jobs) on a title page, 20 at a time (the next ones as the grid scrolls).
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key, required this.type, required this.id, this.crew = false});

  final MediaType type;
  final int id;

  /// « Équipe technique » (`/titre/:type/:id/equipe`), else « Distribution »
  /// (`/titre/:type/:id/distribution`).
  final bool crew;

  static String location(MediaType type, int id, {bool crew = false}) =>
      '/titre/${type.name}/$id/${crew ? 'equipe' : 'distribution'}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);

    return _SeeAllPage(
      heading: crew ? 'Équipe technique' : 'Distribution',
      content: PagedGrid<Person>(
        page: (page) => crew ? titleCrewProvider((type, id, page)) : titleCreditsProvider((type, id, page)),
        // An actor in two roles: twice, once for each.
        idOf: (person) => '${person.id}:${person.role}',
        // The same cards as the title page's row, as many per line as fit.
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: PersonCard.widthOf(layout) + layout.cardGap,
          mainAxisExtent: PersonCard.heightOf(layout) + layout.cardGap,
        ),
        itemBuilder: (_, person) => Align(
          alignment: Alignment.topCenter,
          child: PersonCard(person: person, role: person.role),
        ),
        empty: const EmptyState(icon: Icons.people_outline_rounded, title: 'Aucune personne à afficher'),
      ),
    );
  }
}

/// A « Voir tout » page: back button, the row's title, then [content] (a sliver), the end of the
/// page clear of what covers it.
class _SeeAllPage extends StatelessWidget {
  const _SeeAllPage({required this.heading, required this.content});

  final String heading;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
          slivers: [
            // Room for « Retour », which stays at the top (below).
            SliverToBoxAdapter(child: SizedBox(height: VxFloatingBar.heightOf(layout))),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.gutter,
                  layout.space(VxSpace.m),
                  layout.gutter,
                  layout.space(VxSpace.m),
                ),
                child: Text(heading, style: VxText.title(layout.pageTitleSize)),
              ),
            ),
            content,
            SliverToBoxAdapter(child: SizedBox(height: pageBottomPadding(context))),
          ],
            ),
            // « Retour » stays at the top while the page scrolls under it (TV: the focus on arrival).
            Positioned(top: 0, left: 0, right: 0, child: VxFloatingBar(backAutofocus: layout.isLarge)),
          ],
        ),
      ),
    );
  }
}

/// Title cards loaded page by page ([PagedGrid]).
class _PagedTitles extends ConsumerWidget {
  const _PagedTitles({required this.page, this.empty});

  final FutureProvider<Paged<MediaItem>> Function(int page) page;

  /// Default: « Rien à afficher pour l’instant ».
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    return PagedGrid<MediaItem>(
      page: page,
      idOf: (item) => (item.type, item.id),
      gridDelegate: posterGridDelegate(layout, captionHeight: PosterCard.captionHeightOf(context)),
      itemBuilder: (_, item) => LayoutBuilder(
        builder: (_, c) => PosterCard(item: item, width: c.maxWidth),
      ),
      empty: empty ?? const EmptyState(icon: Icons.movie_filter_outlined, title: 'Rien à afficher pour l’instant'),
    );
  }
}
