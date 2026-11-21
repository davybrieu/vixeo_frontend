import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
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

/// "Voir tout" of « Connu pour » (most voted first) or « Filmographie » (newest first) on a
/// person page: every title of the person.
class PersonTitlesScreen extends ConsumerWidget {
  const PersonTitlesScreen({super.key, required this.id, required this.sort});

  final int id;
  final PersonCreditsSort sort;

  static String location(int id, PersonCreditsSort sort) =>
      '/personne/$id/${sort == PersonCreditsSort.popular ? 'connu-pour' : 'filmographie'}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final format = posterFormatOf(ref);
    final key = (id, sort);

    return _SeeAllPage(
      heading: sort == PersonCreditsSort.popular ? 'Connu pour' : 'Filmographie',
      content: _AsyncSliver<List<MediaItem>>(
        value: ref.watch(personCreditsProvider(key)),
        onRetry: () => ref.invalidate(personCreditsProvider(key)),
        data: (titles) {
          if (titles.isEmpty) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: Icons.movie_filter_outlined, title: 'Aucun titre disponible pour ce profil'),
            );
          }
          return _GridPadding(
            sliver: SliverGrid.builder(
              gridDelegate: posterGridDelegate(layout, format, captionHeight: PosterCard.captionHeightOf(context)),
              itemCount: titles.length,
              itemBuilder: (context, i) => LayoutBuilder(
                builder: (context, c) => PosterCard(item: titles[i], width: c.maxWidth, format: format),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "Voir tout" of « Créateur et distribution » on a title page: the director(s) of a movie or the
/// creator(s) of a TV show first, then the whole cast.
class CreditsScreen extends ConsumerWidget {
  const CreditsScreen({super.key, required this.type, required this.id, this.title});

  final MediaType type;
  final int id;

  /// The row's title (« Créateur et distribution » or « Distribution »); without it (address typed
  /// by hand), chosen once the people are known.
  final String? title;

  static String location(MediaType type, int id, String title) =>
      '/titre/${type.name}/$id/distribution?titre=${Uri.encodeQueryComponent(title)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final key = (type, id);
    final credits = ref.watch(titleCreditsProvider(key));
    final crewRole = type == MediaType.movie ? 'Réalisation' : 'Création';
    final hasCrew = credits.value?.crew.isNotEmpty ?? true;
    final given = title?.trim() ?? '';

    return _SeeAllPage(
      heading: given.isNotEmpty ? given : (hasCrew ? 'Créateur et distribution' : 'Distribution'),
      content: _AsyncSliver<TitleCredits>(
        value: credits,
        onRetry: () => ref.invalidate(titleCreditsProvider(key)),
        data: (credits) {
          final people = [for (final p in credits.crew) (p, crewRole), for (final p in credits.cast) (p, p.role)];
          if (people.isEmpty) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(icon: Icons.people_outline_rounded, title: 'Aucune personne à afficher'),
            );
          }
          return _GridPadding(
            sliver: SliverGrid.builder(
              // The same cards as the title page's row, as many per line as fit.
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: PersonCard.widthOf(layout) + layout.cardGap,
                mainAxisExtent: PersonCard.heightOf(layout) + layout.cardGap,
              ),
              itemCount: people.length,
              itemBuilder: (_, i) => Align(
                alignment: Alignment.topCenter,
                child: PersonCard(person: people[i].$1, role: people[i].$2),
              ),
            ),
          );
        },
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
    final s = layout.isLarge ? layout.scale * 2 : 1.0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.xs), layout.gutter, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VxFocusable(
                    borderRadius: 22 * s,
                    semanticLabel: 'Retour',
                    autofocus: layout.isLarge,
                    onPressed: () => context.canPop() ? context.pop() : context.go('/accueil'),
                    child: Container(
                      width: 44 * s,
                      height: 44 * s,
                      decoration: const BoxDecoration(color: VxColors.surfaceHigh, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_rounded, color: VxColors.text, size: 22 * s),
                    ),
                  ),
                ),
              ),
            ),
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
      ),
    );
  }
}

/// Title cards loaded page by page ([PagedGrid]).
class _PagedTitles extends ConsumerWidget {
  const _PagedTitles({required this.page});

  final FutureProvider<Paged<MediaItem>> Function(int page) page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final format = posterFormatOf(ref);
    return PagedGrid<MediaItem>(
      page: page,
      idOf: (item) => (item.type, item.id),
      gridDelegate: posterGridDelegate(layout, format, captionHeight: PosterCard.captionHeightOf(context)),
      itemBuilder: (_, item) => LayoutBuilder(
        builder: (_, c) => PosterCard(item: item, width: c.maxWidth, format: format),
      ),
      empty: const EmptyState(icon: Icons.movie_filter_outlined, title: 'Rien à afficher pour l’instant'),
    );
  }
}

/// A list loaded at once: a loading circle, the API's error with « Réessayer », then [data].
class _AsyncSliver<T> extends StatelessWidget {
  const _AsyncSliver({required this.value, required this.onRetry, required this.data});

  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final Widget Function(T value) data;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return data(value.value as T);
    if (value.hasError && !value.isLoading) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ErrorPanel(error: value.error!, onRetry: onRetry),
      );
    }
    return const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
  }
}

/// The grid's side margins, and room for the focus zoom on TV (like [PagedGrid]).
class _GridPadding extends StatelessWidget {
  const _GridPadding({required this.sliver});

  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(layout.gutter, layout.isLarge ? layout.tv(16) : 0, layout.gutter, 0),
      sliver: sliver,
    );
  }
}
