import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';
import 'catalog_repository.dart';
import 'list_screen.dart';
import 'description_screen.dart';
import 'models.dart';
import 'widgets.dart';

String personPath(int id) => '/personne/$id';

/// Actor / director page: photo, biography, best-known titles and filmography.
class PersonScreen extends ConsumerWidget {
  const PersonScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = ref.watch(personProvider(id));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AsyncView(
          value: person,
          onRetry: () => ref.invalidate(personProvider(id)),
          data: (p) => _PersonView(person: p),
        ),
      ),
    );
  }
}

class _PersonView extends ConsumerStatefulWidget {
  const _PersonView({required this.person});

  final PersonDetails person;

  @override
  ConsumerState<_PersonView> createState() => _PersonViewState();
}

class _PersonViewState extends ConsumerState<_PersonView> {
  /// Number of posters shown in each row; the rest is behind « Voir tout ».
  static const _rowLength = 20;

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    final photoWidth = layout.isLarge ? layout.tv(300) : (layout.isPhone ? 132.0 : 170.0);

    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(16 * s),
      child: SizedBox(
        width: photoWidth,
        height: photoWidth * 1.5,
        child: NetImage(
          url: p.profileUrl,
          seed: p.id,
          fallback: Center(child: Text(_initials(p.name), style: VxText.title(photoWidth * 0.3))),
        ),
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.name, style: VxText.title(layout.isLarge ? layout.tv(72) : 28, weight: FontWeight.w800)),
        if (p.department != null) ...[
          SizedBox(height: layout.space(VxSpace.xs)),
          Text(
            p.department!,
            style: VxText.body(15 * s, weight: FontWeight.w600, color: VxColors.accent),
          ),
        ],
        if (p.lifeLine != null) ...[
          SizedBox(height: layout.space(VxSpace.xs)),
          Text(p.lifeLine!, style: VxText.body(14 * s, color: VxColors.textSecondary)),
        ],
        if (p.biography != null && !layout.isPhone) ...[
          SizedBox(height: layout.space(VxSpace.m)),
          DescriptionLink(title: p.name, description: p.biography!, maxWidth: layout.tv(1000)),
        ],
      ],
    );

    final page = CustomScrollView(
      slivers: [
        // Room for « Retour », which stays at the top (below).
        SliverToBoxAdapter(child: SizedBox(height: VxFloatingBar.heightOf(layout))),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.m), layout.gutter, layout.sectionGap),
            child: Row(
              crossAxisAlignment: layout.isPhone ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                photo,
                // Between the photo and its text.
                SizedBox(width: layout.space(VxSpace.l)),
                Expanded(child: info),
              ],
            ),
          ),
        ),
        if (p.biography != null && layout.isPhone)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.sectionGap),
              child: DescriptionLink(title: p.name, description: p.biography!),
            ),
          ),
        // Rows scrolled left to right like the home's, each with « Voir tout » (every title of
        // the person, most voted or newest first).
        if (p.movies.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: layout.sectionGap),
              child: PosterRow(
                title: 'Films',
                items: p.movies.take(_rowLength).toList(),
                onSeeAll: () => context.push(PersonTitlesScreen.location(p.id, PersonCreditsType.movie)),
              ),
            ),
          ),
        if (p.shows.isNotEmpty)
          SliverToBoxAdapter(
            child: PosterRow(
              title: 'Séries',
              items: p.shows.take(_rowLength).toList(),
              onSeeAll: () => context.push(PersonTitlesScreen.location(p.id, PersonCreditsType.tv)),
            ),
          ),
        if (p.movies.isEmpty && p.shows.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(icon: Icons.movie_filter_outlined, title: 'Aucun titre disponible pour ce profil'),
          ),
        // The end of the page clear of the tab bar.
        SliverToBoxAdapter(child: SizedBox(height: pageBottomPadding(context))),
      ],
    );
    // « Retour » stays at the top while the page scrolls under it (TV: the focus on arrival).
    return Stack(
      children: [
        page,
        Positioned(top: 0, left: 0, right: 0, child: VxFloatingBar(backAutofocus: layout.isLarge)),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return parts.take(2).map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
  }
}
