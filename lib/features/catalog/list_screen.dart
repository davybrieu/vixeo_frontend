import 'package:flutter/material.dart';
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
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    final format = posterFormatOf(ref);
    final heading = (title == null || title!.trim().isEmpty) ? (type == MediaType.movie ? 'Films' : 'Séries') : title!;

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
            PagedGrid<MediaItem>(
              page: (page) => titleListProvider((type, list, page)),
              idOf: (item) => item.id,
              gridDelegate: posterGridDelegate(layout, format, captionHeight: PosterCard.captionHeightOf(context)),
              itemBuilder: (_, item) => LayoutBuilder(
                builder: (_, c) => PosterCard(item: item, width: c.maxWidth, format: format),
              ),
              empty: const EmptyState(icon: Icons.movie_filter_outlined, title: 'Rien à afficher pour l’instant'),
            ),
            // The end of the page clear of what covers it.
            SliverToBoxAdapter(child: SizedBox(height: pageBottomPadding(context))),
          ],
        ),
      ),
    );
  }
}
