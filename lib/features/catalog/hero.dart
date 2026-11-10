import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
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
  final _controller = PageController(viewportFraction: 1.0);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A full-bleed hero that uses most of the phone's first screen, like the native TV apps.
    final height = MediaQuery.sizeOf(context).height * 0.58;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _FeaturedCard(item: widget.items[i]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? Colors.white : Colors.white.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedCard extends ConsumerWidget {
  const _FeaturedCard({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Home items bring their length, genres and age rating; otherwise (TMDb failed) the title page.
    final details = item.summary == null ? ref.watch(titleProvider((item.type, item.id))).value : null;
    final summary = item.summary ?? (details == null ? null : TitleSummary.of(details));
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The poster without text if there is one: the logo below is the title.
          NetImage(url: item.backdrop('w1280'), seed: item.id),
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
            bottom: 62,
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
                TitleFacts(
                  rating: details?.voteAverage ?? item.voteAverage,
                  year: details?.year ?? item.year,
                  summary: summary,
                  fontSize: 14,
                  spacing: 10,
                  gap: 6,
                  genreFontSize: 14,
                  badgeFontSize: 12,
                ),
                const SizedBox(height: VxSpace.m),
                Row(
                  children: [
                    Expanded(
                      child: VxButton(
                        label: 'Voir la fiche',
                        icon: Icons.info_outline_rounded,
                        expand: true,
                        onPressed: () => context.push(titlePath(item.type, item.id)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Same round icon buttons as on the title page.
                    FavoriteButton(item: item),
                    const SizedBox(width: 12),
                    LikedButton(item: item),
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

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final item = widget.item;
    // Home and search items bring their logo, length, genres and age rating: shown at once.
    // "Continuer à regarder" items don't: the title page brings them when the selection rests.
    final details = item.summary == null && _settled ? ref.watch(titleProvider((item.type, item.id))).value : null;
    final summary = item.summary ?? (details == null ? null : TitleSummary.of(details));
    final logoUrl = item.logoUrl ?? details?.logoUrl;
    final logoRatio = item.logoUrl != null ? item.logoAspectRatio : details?.logoAspectRatio;
    final slot = layout.tv(widget.compact ? 90 : 120);
    final overview = details?.overview ?? item.overview;

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
              TitleFacts(
                rating: details?.voteAverage ?? item.voteAverage,
                year: details?.year ?? item.year,
                summary: summary,
                fontSize: layout.tv(22),
                spacing: layout.tv(18),
                gap: layout.tv(12),
                genreFontSize: layout.tv(20),
                badgeFontSize: layout.tv(18),
                maxGenres: 3,
              ),
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

/// Rating, year, length and age rating, then the genres, shown together once the [summary] is
/// known (with the list item, or from the title page): nothing appears piece by piece. Until then,
/// an empty space of the same height keeps the lines below in place.
class TitleFacts extends StatelessWidget {
  const TitleFacts({
    super.key,
    required this.rating,
    required this.year,
    required this.summary,
    required this.fontSize,
    required this.spacing,
    required this.gap,
    required this.genreFontSize,
    required this.badgeFontSize,
    this.maxGenres,
  });

  final double rating;
  final int? year;
  final TitleSummary? summary;
  final double fontSize;

  /// Between the facts of the first line.
  final double spacing;

  /// Between the two lines.
  final double gap;
  final double genreFontSize;
  final double badgeFontSize;
  final int? maxGenres;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final meta = VxText.body(fontSize, color: VxColors.textSoft);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
      child: summary == null
          ? SizedBox(key: const ValueKey('waiting'), height: fontSize * 1.6 + gap + genreFontSize * 1.45)
          : Column(
              key: const ValueKey('facts'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: spacing,
                  runSpacing: fontSize * 0.4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (rating > 0) TmdbRating(rating, fontSize: fontSize),
                    if (year != null) Text('$year', style: meta),
                    if (summary.length != null) Text(summary.length!, style: meta),
                    if (summary.ageLabel != null) VxBadge(summary.ageLabel!, outlined: true, fontSize: badgeFontSize),
                  ],
                ),
                if (summary.genres.isNotEmpty) ...[
                  SizedBox(height: gap),
                  Text(
                    (maxGenres == null ? summary.genres : summary.genres.take(maxGenres!)).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(genreFontSize, color: VxColors.textSecondary),
                  ),
                ],
              ],
            ),
    );
  }
}
