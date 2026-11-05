import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../library/actions.dart';
import 'catalog_repository.dart';
import 'models.dart';
import 'widgets.dart';

/// Title shown in the hero of a large screen (home, search): the selected (focused) card at once,
/// or the hovered one once the pointer rests on it, so sweeping across a row doesn't flicker.
class HeroSelection {
  HeroSelection([MediaItem? initial]) : item = ValueNotifier(initial);

  final ValueNotifier<MediaItem?> item;
  Timer? _hoverTimer;

  /// Remote or keyboard: the hero follows at once.
  void select(MediaItem? value) {
    if (value == null) return;
    _hoverTimer?.cancel();
    item.value = value;
  }

  /// Mouse: after 150 ms on the card.
  void hover(MediaItem? value) {
    if (value == null) return;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 150), () => item.value = value);
  }

  /// New results: back to [value] (or nothing).
  void reset([MediaItem? value]) {
    _hoverTimer?.cancel();
    item.value = value;
  }

  void dispose() {
    _hoverTimer?.cancel();
    item.dispose();
  }
}

/// Phone home: swipeable cards of featured titles.
class FeaturedCarousel extends StatefulWidget {
  const FeaturedCarousel({super.key, required this.items});

  final List<MediaItem> items;

  @override
  State<FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<FeaturedCarousel> {
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
                // The logo of the title (given with the home rows), else its name.
                LayoutBuilder(
                  builder: (_, c) => TitleLogo(
                    name: item.title,
                    logoUrl: item.logoUrl,
                    size: TitleLogo.sizeFor(
                      item.logoUrl,
                      item.logoAspectRatio,
                      maxWidth: c.maxWidth * 0.85,
                      maxHeight: 84,
                    ),
                    maxLines: 2,
                    style: VxText.title(32, weight: FontWeight.w800),
                  ),
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

/// Large screens: backdrop of the hero's title, faded into the page on the left and at the bottom.
class HeroBackdrop extends StatelessWidget {
  const HeroBackdrop({super.key, required this.item});

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

/// Information of the title in the hero (no button: the card itself opens the title page). The
/// list item gives the essentials at once; when the selection rests for a moment, the title's page
/// adds genres, length and age rating (fetched only then, not for every card passed over).
class HeroText extends ConsumerStatefulWidget {
  const HeroText({super.key, required this.item, this.compact = false});

  final MediaItem item;

  /// Below other content (search page): no top margin and a smaller title.
  final bool compact;

  @override
  ConsumerState<HeroText> createState() => _HeroTextState();
}

class _HeroTextState extends ConsumerState<HeroText> {
  static const _settleDelay = Duration(milliseconds: 400);

  Timer? _timer;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _waitForSettle();
  }

  @override
  void didUpdateWidget(HeroText old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id || old.item.type != widget.item.type) {
      _settled = false;
      _waitForSettle();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _waitForSettle() {
    _timer?.cancel();
    _timer = Timer(_settleDelay, () {
      if (mounted) setState(() => _settled = true);
    });
  }

  static String _age(int age) => age == 0 ? 'Tous publics' : '$age+';

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final item = widget.item;
    final details = _settled ? ref.watch(titleProvider((item.type, item.id))).value : null;
    // Home rows give the logo at once; elsewhere (search, "Continuer à regarder") the title page
    // brings it once the selection rests.
    final logoUrl = item.logoUrl ?? details?.logoUrl;
    final logoRatio = item.logoUrl != null ? item.logoAspectRatio : details?.logoAspectRatio;
    final slot = layout.tv(widget.compact ? 90 : 120);

    final rating = details?.voteAverage ?? item.voteAverage;
    final year = details?.year ?? item.year;
    final overview = details?.overview ?? item.overview;
    final length = switch (details) {
      final d? when d.type == MediaType.movie && d.runtime != null => formatRuntime(d.runtime),
      final d? when d.type == MediaType.tv && d.numberOfSeasons > 0 =>
        '${d.numberOfSeasons} saison${d.numberOfSeasons > 1 ? 's' : ''}',
      _ => null,
    };
    final genres = details?.genres.take(3).map((g) => g.name).join(' · ') ?? '';
    final meta = VxText.body(layout.tv(22), color: VxColors.textSoft);

    return Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, layout.tv(widget.compact ? 0 : 110), layout.gutter, layout.tv(24)),
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
              // Logo of the title, else its name: in a slot of fixed height, so the lines below
              // don't move when the logo arrives.
              SizedBox(
                height: slot,
                width: double.infinity,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  layoutBuilder: (current, previous) =>
                      Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
                  child: TitleLogo(
                    key: ValueKey((item.type, item.id, logoUrl)),
                    name: item.title,
                    logoUrl: logoUrl,
                    size: TitleLogo.sizeFor(logoUrl, logoRatio, maxWidth: layout.tv(700), maxHeight: slot),
                    maxLines: 1,
                    style: VxText.title(layout.tv(widget.compact ? 64 : 88), weight: FontWeight.w800),
                  ),
                ),
              ),
              SizedBox(height: layout.tv(20)),
              Wrap(
                spacing: layout.tv(18),
                runSpacing: layout.tv(8),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (rating > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: VxColors.accent, size: layout.tv(26)),
                        SizedBox(width: layout.tv(6)),
                        Text(formatRating(rating), style: VxText.body(layout.tv(22), weight: FontWeight.w600)),
                      ],
                    ),
                  if (year != null) Text('$year', style: meta),
                  if (length != null) Text(length, style: meta),
                  if (details?.ageRating != null)
                    VxBadge(_age(details!.ageRating!), outlined: true, fontSize: layout.tv(18)),
                ],
              ),
              if (genres.isNotEmpty) ...[
                SizedBox(height: layout.tv(12)),
                Text(
                  genres,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(layout.tv(20), color: VxColors.textSecondary),
                ),
              ],
              if (overview != null) ...[
                SizedBox(height: layout.tv(20)),
                Text(
                  overview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VxText.body(layout.tv(24), color: VxColors.textSoft),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
