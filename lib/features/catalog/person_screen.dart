import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/expandable_text.dart';
import '../../core/widgets/page_header.dart';
import '../auth/session.dart';
import '../library/actions.dart';
import 'catalog_repository.dart';
import 'list_screen.dart';
import 'models.dart';
import 'widgets.dart';

String personPath(int id) => '/personne/$id';

/// Actor / director page: photo, « Suivre » (signed in with a profile), biography, best-known
/// titles, filmography.
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
  /// Titles of the « Filmographie » row (newest first), like a home row: the rest is behind
  /// « Voir tout ».
  static const _rowLength = 20;

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    final photoWidth = layout.isLarge ? layout.tv(300) : (layout.isPhone ? 132.0 : 170.0);
    final session = ref.watch(sessionProvider);
    final canFollow = session.isSignedIn && session.profile != null;

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
        if (canFollow) ...[
          SizedBox(height: layout.space(VxSpace.m)),
          FollowPersonButton(
            person: Person(id: p.id, name: p.name, profileUrl: p.profileUrl),
          ),
        ],
        if (p.biography != null && !layout.isPhone) ...[
          SizedBox(height: layout.space(VxSpace.m)),
          ExpandableText(text: p.biography!, maxWidth: layout.tv(1000)),
        ],
      ],
    );

    return CustomScrollView(
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
              child: ExpandableText(text: p.biography!),
            ),
          ),
        // Rows scrolled left to right like the home's, each with « Voir tout » (every title of
        // the person, most voted or newest first).
        if (p.knownFor.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: layout.sectionGap),
              child: PosterRow(
                title: 'Connu pour',
                items: p.knownFor,
                onSeeAll: () => context.push(PersonTitlesScreen.location(p.id, PersonCreditsSort.popular)),
              ),
            ),
          ),
        if (p.filmography.isNotEmpty)
          SliverToBoxAdapter(
            child: PosterRow(
              title: 'Filmographie',
              items: p.filmography.take(_rowLength).toList(),
              onSeeAll: () => context.push(PersonTitlesScreen.location(p.id, PersonCreditsSort.date)),
            ),
          ),
        if (p.knownFor.isEmpty && p.filmography.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(icon: Icons.movie_filter_outlined, title: 'Aucun titre disponible pour ce profil'),
          ),
        // The end of the page clear of the tab bar.
        SliverToBoxAdapter(child: SizedBox(height: pageBottomPadding(context))),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return parts.take(2).map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
  }
}
