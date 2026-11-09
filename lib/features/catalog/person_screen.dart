import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/expandable_text.dart';
import 'catalog_repository.dart';
import 'models.dart';
import 'widgets.dart';

String personPath(int id) => '/personne/$id';

/// Actor / director page: photo, biography, best-known titles, filmography.
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
  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    final format = posterFormatOf(ref);
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
          SizedBox(height: 8 * s),
          Text(
            p.department!,
            style: VxText.body(15 * s, weight: FontWeight.w600, color: VxColors.accent),
          ),
        ],
        if (p.lifeLine != null) ...[
          SizedBox(height: 8 * s),
          Text(p.lifeLine!, style: VxText.body(14 * s, color: VxColors.textSecondary)),
        ],
        if (p.biography != null && !layout.isPhone) ...[
          SizedBox(height: 16 * s),
          ExpandableText(text: p.biography!, maxWidth: layout.tv(1000)),
        ],
      ],
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 8 * s, layout.gutter, 0),
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
            padding: EdgeInsets.fromLTRB(layout.gutter, 16 * s, layout.gutter, 24 * s),
            child: Row(
              crossAxisAlignment: layout.isPhone ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                photo,
                SizedBox(width: (layout.isPhone ? 18 : 40) * s),
                Expanded(child: info),
              ],
            ),
          ),
        ),
        if (p.biography != null && layout.isPhone)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 24),
              child: ExpandableText(text: p.biography!),
            ),
          ),
        if (p.knownFor.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 24 * s),
              child: PosterRow(title: 'Connu pour', items: p.knownFor),
            ),
          ),
        if (p.filmography.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Filmographie')),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 40 * s),
            sliver: SliverGrid.builder(
              gridDelegate: posterGridDelegate(layout, format),
              itemCount: p.filmography.length,
              itemBuilder: (context, i) => LayoutBuilder(
                builder: (context, c) => PosterCard(item: p.filmography[i], width: c.maxWidth, format: format),
              ),
            ),
          ),
        ],
        if (p.knownFor.isEmpty && p.filmography.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(icon: Icons.movie_filter_outlined, title: 'Aucun titre disponible pour ce profil'),
          ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return parts.take(2).map((w) => String.fromCharCode(w.runes.first).toUpperCase()).join();
  }
}
