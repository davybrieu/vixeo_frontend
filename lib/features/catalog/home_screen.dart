import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/common.dart';
import '../library/library.dart';
import '../tv/channel_row.dart';
import 'catalog_repository.dart';
import 'hero.dart';
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
    // Live channels by theme (généralistes, sport, info, enfants), under « Continuer à regarder ».
    final channels = ref.watch(homeChannelSectionsProvider).value ?? const <ChannelSection>[];
    final layout = Layout.of(context);

    Future<void> refresh() async {
      ref.invalidate(homeProvider(type));
      await Future.wait([ref.read(homeProvider(type).future), ref.read(libraryProvider.notifier).refresh()]);
    }

    return AsyncView(
      value: home,
      onRetry: () => ref.invalidate(homeProvider(type)),
      data: (data) {
        if (data.sections.isEmpty && data.featured.isEmpty && channels.isEmpty) {
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
                child: _PhoneHome(home: data, resume: rows, channels: channels, type: type),
              )
            : _LargeHome(home: data, resume: rows, channels: channels, type: type);
      },
    );
  }
}

// ───────────────────────────── Phone ─────────────────────────────

class _PhoneHome extends StatelessWidget {
  const _PhoneHome({required this.home, required this.resume, required this.channels, required this.type});

  final Home home;
  final List<ProfileItem> resume;
  final List<ChannelSection> channels;
  final MediaType? type;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final gap = SizedBox(height: layout.sectionGap);
    return ListView(
      // The last row ends above the tab bar.
      padding: EdgeInsets.only(bottom: pageBottomPadding(context)),
      children: [
        if (home.featured.isNotEmpty) FeaturedCarousel(items: home.featured),
        if (resume.isNotEmpty) ...[
          gap,
          const SectionHeader('Continuer à regarder'),
          SizedBox(
            height: 124 + 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              itemCount: resume.length,
              separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
              itemBuilder: (_, i) => ResumeCard(item: resume[i], width: 220),
            ),
          ),
        ],
        for (final section in channels) ...[gap, ChannelRow(title: section.title, channels: section.channels)],
        for (final section in home.sections) ...[gap, PosterRow(title: section.title, items: section.items)],
      ],
    );
  }
}

// ───────────────────────────── TV / large ─────────────────────────────

class _LargeHome extends StatefulWidget {
  const _LargeHome({required this.home, required this.resume, required this.channels, required this.type});

  final Home home;
  final List<ProfileItem> resume;
  final List<ChannelSection> channels;
  final MediaType? type;

  @override
  State<_LargeHome> createState() => _LargeHomeState();
}

class _LargeHomeState extends State<_LargeHome> {
  /// On arrival, the first card of the first row, which also has the focus ("Continuer à
  /// regarder" if any, else the first list).
  late final _hero = HeroSelection(
    widget.resume.firstOrNull?.asMediaItem ??
        widget.home.sections.firstOrNull?.items.firstOrNull ??
        widget.home.featured.firstOrNull,
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
            valueListenable: _hero.item,
            builder: (_, item, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: HeroBackdrop(key: ValueKey(item?.id), item: item),
            ),
          ),
        ),
        Column(
          children: [
            SizedBox(
              height: layout.tv(500),
              child: ValueListenableBuilder(
                valueListenable: _hero.item,
                builder: (_, item, _) => item == null ? const SizedBox() : HeroText(item: item),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(bottom: pageBottomPadding(context)),
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
                          separatorBuilder: (_, _) => SizedBox(width: layout.cardGap),
                          itemBuilder: (_, i) => ResumeCard(
                            item: widget.resume[i],
                            width: layout.tv(384),
                            autofocus: i == 0,
                            onFocused: () => _hero.select(widget.resume[i].asMediaItem),
                            onHovered: () => _hero.hover(widget.resume[i].asMediaItem),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: layout.sectionGap),
                  ],
                  for (final section in widget.channels) ...[
                    ChannelRow(title: section.title, channels: section.channels),
                    SizedBox(height: layout.sectionGap),
                  ],
                  for (final (index, section) in widget.home.sections.indexed) ...[
                    PosterRow(
                      title: section.title,
                      items: section.items,
                      onFocused: _hero.select,
                      onHovered: _hero.hover,
                      // Nothing to resume: the first card of the first list takes the focus.
                      autofocusFirst: index == 0 && widget.resume.isEmpty,
                    ),
                    if (index < widget.home.sections.length - 1) SizedBox(height: layout.sectionGap),
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
