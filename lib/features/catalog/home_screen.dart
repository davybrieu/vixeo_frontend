import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../library/actions.dart';
import '../library/library.dart';
import 'catalog_repository.dart';
import 'models.dart';
import 'widgets.dart';

/// Home: featured titles, "Continuer à regarder", themed rows.
/// [type] limits it to movies or TV shows.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.type});

  final MediaType? type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider(type));
    final resume = ref.watch(libraryProvider).value?.continueWatching ?? const <ProfileItem>[];
    final layout = Layout.of(context);

    Future<void> refresh() async {
      ref.invalidate(homeProvider(type));
      await Future.wait([ref.read(homeProvider(type).future), ref.read(libraryProvider.notifier).refresh()]);
    }

    return AsyncView(
      value: home,
      onRetry: () => ref.invalidate(homeProvider(type)),
      data: (data) {
        if (data.sections.isEmpty && data.featured.isEmpty) {
          return const EmptyState(
            icon: Icons.movie_filter_outlined,
            title: 'Rien à afficher pour l’instant',
            message: 'Le catalogue est vide pour ce profil.',
          );
        }
        // Continue watching only lists what matches this home (movies, TV shows or both).
        final rows = type == null ? resume : resume.where((i) => i.tmdbTitle?.type == type).toList();
        return layout.isPhone
            ? RefreshIndicator(
                onRefresh: refresh,
                child: _PhoneHome(home: data, resume: rows, type: type),
              )
            : _LargeHome(home: data, resume: rows, type: type);
      },
    );
  }
}

// ───────────────────────────── Phone ─────────────────────────────

class _PhoneHome extends StatelessWidget {
  const _PhoneHome({required this.home, required this.resume, required this.type});

  final Home home;
  final List<ProfileItem> resume;
  final MediaType? type;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ListView(
      padding: EdgeInsets.only(top: top + 8, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              const VxLogo(size: 22),
              const Spacer(),
              _TypeChips(type: type),
            ],
          ),
        ),
        if (home.featured.isNotEmpty) _FeaturedCarousel(items: home.featured),
        if (resume.isNotEmpty) ...[
          const SizedBox(height: 28),
          const SectionHeader('Continuer à regarder'),
          SizedBox(
            height: 124 + 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: resume.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => ResumeCard(item: resume[i], width: 220),
            ),
          ),
        ],
        for (final section in home.sections) ...[
          const SizedBox(height: 24),
          PosterRow(title: section.title, items: section.items),
        ],
      ],
    );
  }
}

class _TypeChips extends StatelessWidget {
  const _TypeChips({required this.type});

  final MediaType? type;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, MediaType value, String path) {
      final selected = type == value;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: VxFocusable(
          borderRadius: 18,
          semanticLabel: label,
          onPressed: () => context.go(selected ? '/accueil' : path),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? VxColors.accent.withValues(alpha: 0.14) : Colors.transparent,
              border: selected ? null : Border.all(color: VxColors.lineStrong),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              style: VxText.body(
                14,
                weight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? VxColors.accent : VxColors.text,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [chip('Films', MediaType.movie, '/films'), chip('Séries', MediaType.tv, '/series')],
    );
  }
}

class _FeaturedCarousel extends StatefulWidget {
  const _FeaturedCarousel({required this.items});

  final List<MediaItem> items;

  @override
  State<_FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<_FeaturedCarousel> {
  final _controller = PageController(viewportFraction: 0.9);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.9 - 12;
    final height = (width * 1.3).clamp(320, 520).toDouble();
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _FeaturedCard(item: widget.items[i]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? VxColors.accent : VxColors.lineStrong,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetImage(url: item.poster('w780'), seed: item.id),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xEB070A08)],
                stops: [0.35, 1],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.title(32, weight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    item.type.label,
                    if (item.year != null) '${item.year}',
                    if (item.voteAverage > 0) '★ ${formatRating(item.voteAverage)}',
                  ].join(' · '),
                  style: VxText.body(14, color: VxColors.textSoft),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: VxButton(
                        label: 'Lecture',
                        icon: Icons.play_arrow_rounded,
                        expand: true,
                        onPressed: () => context.push(titlePath(item.type, item.id)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Same round icon button as on the title page.
                    FavoriteButton(item: item),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── TV / large ─────────────────────────────

class _LargeHome extends StatefulWidget {
  const _LargeHome({required this.home, required this.resume, required this.type});

  final Home home;
  final List<ProfileItem> resume;
  final MediaType? type;

  @override
  State<_LargeHome> createState() => _LargeHomeState();
}

class _LargeHomeState extends State<_LargeHome> {
  /// Title shown in the hero: the focused poster, else the first featured one.
  late final ValueNotifier<MediaItem?> _hero = ValueNotifier(
    widget.home.featured.firstOrNull ?? widget.home.sections.firstOrNull?.items.firstOrNull,
  );

  @override
  void dispose() {
    _hero.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);

    // The info panel stays on top; only the rows scroll under it, so the
    // focused title's name and overview are always visible (TV pattern).
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: layout.tv(760),
          child: ValueListenableBuilder(
            valueListenable: _hero,
            builder: (_, item, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: _HeroBackdrop(key: ValueKey(item?.id), item: item),
            ),
          ),
        ),
        Column(
          children: [
            SizedBox(
              height: layout.tv(580),
              child: ValueListenableBuilder(
                valueListenable: _hero,
                builder: (_, item, _) =>
                    item == null ? const SizedBox() : _HeroText(item: item, autofocus: widget.resume.isEmpty),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(bottom: layout.tv(80)),
                children: [
                  if (widget.resume.isNotEmpty) ...[
                    const SectionHeader('Continuer à regarder'),
                    FocusTraversalGroup(
                      child: SizedBox(
                        height: layout.tv(216 + 32),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: layout.tv(16)),
                          itemCount: widget.resume.length,
                          separatorBuilder: (_, _) => SizedBox(width: layout.tv(32)),
                          itemBuilder: (_, i) =>
                              ResumeCard(item: widget.resume[i], width: layout.tv(384), autofocus: i == 0),
                        ),
                      ),
                    ),
                    SizedBox(height: layout.tv(36)),
                  ],
                  for (final (index, section) in widget.home.sections.indexed) ...[
                    PosterRow(title: section.title, items: section.items, onFocused: (item) => _hero.value = item),
                    if (index < widget.home.sections.length - 1) SizedBox(height: layout.tv(36)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({super.key, required this.item});

  final MediaItem? item;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      NetImage(url: item?.backdrop('original'), seed: item?.id ?? 0),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [VxColors.background, Color(0xE0070A08), Color(0x33070A08), Colors.transparent],
            stops: [0, 0.32, 0.62, 1],
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
  );
}

class _HeroText extends StatelessWidget {
  const _HeroText({required this.item, this.autofocus = false});

  final MediaItem item;

  /// Focus the button on arrival when nothing else takes the focus.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, layout.tv(110), layout.gutter, layout.tv(24)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: layout.tv(860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.type.label.toUpperCase(),
                style: VxText.body(
                  layout.tv(20),
                  weight: FontWeight.w600,
                  color: VxColors.accent,
                ).copyWith(letterSpacing: 1.5),
              ),
              SizedBox(height: layout.tv(16)),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: VxText.title(layout.tv(88), weight: FontWeight.w800),
              ),
              SizedBox(height: layout.tv(20)),
              Row(
                children: [
                  if (item.voteAverage > 0) ...[
                    Icon(Icons.star_rounded, color: VxColors.accent, size: layout.tv(26)),
                    SizedBox(width: layout.tv(6)),
                    Text(formatRating(item.voteAverage), style: VxText.body(layout.tv(22), weight: FontWeight.w600)),
                    SizedBox(width: layout.tv(18)),
                  ],
                  if (item.year != null)
                    Text('${item.year}', style: VxText.body(layout.tv(22), color: VxColors.textSoft)),
                ],
              ),
              if (item.overview != null) ...[
                SizedBox(height: layout.tv(20)),
                Text(
                  item.overview!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(layout.tv(24), color: VxColors.textSoft),
                ),
              ],
              SizedBox(height: layout.tv(28)),
              VxButton(
                label: 'Plus d’infos',
                icon: Icons.info_outline_rounded,
                kind: VxButtonKind.secondary,
                autofocus: autofocus,
                onPressed: () => context.push(titlePath(item.type, item.id)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
