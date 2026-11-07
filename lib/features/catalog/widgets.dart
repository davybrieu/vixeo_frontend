import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../auth/models.dart';
import '../auth/session.dart';
import '../library/actions.dart';
import '../library/library.dart';
import 'catalog_repository.dart';
import 'models.dart';
import 'person_screen.dart';

String titlePath(MediaType type, int id) => '/titre/${type.name}/$id';

/// Title card: vertical poster (2:3) or horizontal image (16:9), following the profile's poster
/// format. The image alone, without the name (developer's choice); the name is written only for
/// a title without any image. Screen readers get the name from the label.
class PosterCard extends ConsumerWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.width,
    this.format = PosterFormat.portrait,
    this.onFocused,
    this.onHovered,
    this.autofocus = false,
  });

  final MediaItem item;
  final double width;
  final PosterFormat format;
  final VoidCallback? onFocused;
  final VoidCallback? onHovered;
  final bool autofocus;

  static double heightFor(double width, PosterFormat format) =>
      format == PosterFormat.portrait ? width * 1.5 : width * 9 / 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemState = ref.watch(
      libraryProvider.select((state) => state.value?.forItem(item)),
    );
    final watched = itemState?.isWatched ?? false;
    final favorite = itemState?.isFavorite ?? false;
    final landscape = format == PosterFormat.landscape;
    final details = landscape ? ref.watch(titleProvider((item.type, item.id))).value : null;
    final logoUrl = item.logoUrl ?? details?.logoUrl;
    final logoAspectRatio = item.logoAspectRatio ?? details?.logoAspectRatio;
    final radius = landscape ? width * 0.05 : width * 0.086;
    final noImage = Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.all(landscape ? width * 0.045 : width * 0.08),
        child: Text(
          item.title,
          maxLines: landscape ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: VxText.title(landscape ? (width * 0.07).clamp(13, 30).toDouble() : width * 0.12),
        ),
      ),
    );

    return VxFocusable(
      autofocus: autofocus,
      borderRadius: radius,
      semanticLabel: '${item.title}, ${item.type.label.toLowerCase()}${item.year != null ? ', ${item.year}' : ''}${watched ? ', vu' : ''}',
      onFocused: onFocused,
      onHovered: onHovered,
      onPressed: () => context.push(titlePath(item.type, item.id)),
      onLongPress: () => showTitleMenu(context, item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: heightFor(width, format),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(
                url: landscape ? (item.backdrop('w780') ?? item.posterUrl) : item.posterUrl,
                seed: item.id,
                fallback: noImage,
              ),
              if (landscape && logoUrl != null) ...[
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xB8070A08)],
                      stops: [0.48, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: width * 0.045,
                  bottom: width * 0.045,
                  child: TitleLogo(
                    name: item.title,
                    logoUrl: logoUrl,
                    size: TitleLogo.sizeFor(
                      logoUrl,
                      logoAspectRatio,
                      maxWidth: width * 0.48,
                      maxHeight: width * 0.17,
                    ),
                    style: VxText.title((width * 0.07).clamp(13, 30).toDouble()),
                    maxLines: 2,
                  ),
                ),
              ],
              if (favorite)
                Positioned(
                  top: width * 0.06,
                  left: width * 0.06,
                  child: Container(
                    width: (width * 0.13).clamp(22, 32).toDouble(),
                    height: (width * 0.13).clamp(22, 32).toDouble(),
                    decoration: const BoxDecoration(
                      color: Color(0xB8070A08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bookmark_added_rounded,
                      color: VxColors.accent,
                      size: 17,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Poster format of the active profile.
PosterFormat posterFormatOf(WidgetRef ref) =>
    ref.watch(sessionProvider.select((s) => s.profile?.posterFormat)) ?? PosterFormat.portrait;

/// Card width in rows, by screen and format.
double rowCardWidth(Layout layout, PosterFormat format) => format == PosterFormat.portrait
    ? (layout.isLarge ? layout.tv(220) : (layout.isPhone ? 116.0 : 140.0))
    : (layout.isLarge ? layout.tv(384) : (layout.isPhone ? 220.0 : 260.0));

/// Horizontal row of title cards, with its title.
class PosterRow extends ConsumerWidget {
  const PosterRow({
    super.key,
    required this.title,
    required this.items,
    this.onFocused,
    this.onHovered,
    this.onSeeAll,
    this.autofocusFirst = false,
  });

  final String title;
  final List<MediaItem> items;

  /// The first card takes the focus on arrival (first row of a screen).
  final bool autofocusFirst;

  /// The remote / keyboard focus, or the mouse, is on [item] (TV home: the hero follows).
  final void Function(MediaItem item)? onFocused;
  final void Function(MediaItem item)? onHovered;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final format = posterFormatOf(ref);
    final width = rowCardWidth(layout, format);
    final gap = layout.isLarge ? layout.tv(28) : 10.0;
    // Room for the focus zoom on TV.
    final vPad = layout.isLarge ? layout.tv(16) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.isLarge ? layout.tv(22) : 12),
          child: Row(
            children: [
              Expanded(child: Text(title, style: VxText.title(layout.isLarge ? layout.tv(30) : 18))),
              if (onSeeAll != null)
                VxFocusable(
                  borderRadius: 8,
                  semanticLabel: 'Voir tout $title',
                  onPressed: onSeeAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Voir tout', style: VxText.body(layout.isLarge ? layout.tv(20) : 13, color: VxColors.accent, weight: FontWeight.w600)),
                        SizedBox(width: layout.isLarge ? layout.tv(6) : 3),
                        Icon(Icons.chevron_right_rounded, size: layout.isLarge ? layout.tv(24) : 18, color: VxColors.accent),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        FocusTraversalGroup(
          child: SizedBox(
            height: PosterCard.heightFor(width, format) + vPad * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: vPad),
              itemCount: items.length,
              separatorBuilder: (_, _) => SizedBox(width: gap),
              itemBuilder: (context, i) => PosterCard(
                item: items[i],
                width: width,
                format: format,
                onFocused: onFocused == null ? null : () => onFocused!(items[i]),
                onHovered: onHovered == null ? null : () => onHovered!(items[i]),
                autofocus: autofocusFirst && i == 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Continuer à regarder" card: backdrop 16:9 + progress bar.
class ResumeCard extends StatelessWidget {
  const ResumeCard({
    super.key,
    required this.item,
    required this.width,
    this.autofocus = false,
    this.onFocused,
    this.onHovered,
  });

  final ProfileItem item;
  final double width;
  final bool autofocus;
  final VoidCallback? onFocused;
  final VoidCallback? onHovered;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final title = item.tmdbTitle;
    final radius = layout.isLarge ? layout.tv(18) : 12.0;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(url: item.backdropUrl ?? item.posterUrl, seed: item.title.hashCode),
            if (layout.isLarge)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD9070A08)],
                    stops: [0.45, 1],
                  ),
                ),
              ),
            if (layout.isLarge)
              Positioned(
                left: layout.tv(20),
                right: layout.tv(20),
                bottom: layout.tv(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: VxText.title(layout.tv(24))),
                    if (item.resumeLabel.isNotEmpty)
                      Text(item.resumeLabel, style: VxText.body(layout.tv(18), color: VxColors.textSoft)),
                  ],
                ),
              )
            else
              Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: Color(0x99070A08), shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, color: VxColors.text),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VxProgressBar(value: item.progress ?? 0, height: layout.isLarge ? layout.tv(6) : 4),
            ),
          ],
        ),
      ),
    );

    return VxFocusable(
      autofocus: autofocus,
      borderRadius: radius,
      semanticLabel: '${item.title}, reprendre. ${item.resumeLabel}',
      onFocused: onFocused,
      onHovered: onHovered,
      onPressed: title == null ? null : () => context.push(titlePath(title.type, title.id)),
      onLongPress: () => showResumeMenu(context, item),
      child: layout.isLarge
          ? image
          : SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  image,
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(14, weight: FontWeight.w600),
                  ),
                  if (item.resumeLabel.isNotEmpty)
                    Text(item.resumeLabel, style: VxText.body(13, color: VxColors.textSecondary)),
                ],
              ),
            ),
    );
  }
}

/// A title written with TMDb's logo when there is one (title page, hero, phone carousel): sized
/// before it loads, so nothing jumps. Without a logo, or if it can't be loaded, the name is written
/// as text. Screen readers always get the name.
class TitleLogo extends StatelessWidget {
  const TitleLogo({
    super.key,
    required this.name,
    required this.logoUrl,
    required this.size,
    required this.style,
    this.maxLines,
  });

  final String name;
  final String? logoUrl;

  /// From [sizeFor]; null = no logo.
  final Size? size;
  final TextStyle style;
  final int? maxLines;

  /// Logo size within [maxWidth] × [maxHeight], keeping its proportions; null without a logo.
  static Size? sizeFor(String? logoUrl, double? aspectRatio, {required double maxWidth, required double maxHeight}) {
    if (logoUrl == null) return null;
    final ratio = (aspectRatio ?? 0) > 0 ? aspectRatio! : 3.0;
    final width = math.min(maxWidth, maxHeight * ratio);
    return Size(width, width / ratio);
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(name, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    final size = this.size;
    if (logoUrl == null || size == null) return text;

    return Semantics(
      header: true,
      label: name,
      child: ExcludeSemantics(
        child: CachedNetworkImage(
          imageUrl: logoUrl!,
          fadeInDuration: const Duration(milliseconds: 200),
          imageBuilder: (_, image) => Image(
            image: image,
            width: size.width,
            height: size.height,
            fit: BoxFit.contain,
            alignment: Alignment.bottomLeft,
          ),
          placeholder: (_, _) => SizedBox(width: size.width, height: size.height),
          errorWidget: (_, _, _) => text,
        ),
      ),
    );
  }
}

/// Person card (cast, director, search results): round photo or initials, name on up to two
/// lines and, if given, the role. Opens the person's page.
class PersonCard extends StatelessWidget {
  const PersonCard({super.key, required this.person, this.role});

  final Person person;

  /// Character, or "Réalisation" / "Création"; null = name only.
  final String? role;

  static double avatarOf(Layout layout) => layout.isLarge ? layout.tv(150) : 84;

  static double widthOf(Layout layout) => layout.isLarge ? layout.tv(210) : 108;

  /// Room for the photo, two lines of name and two lines of role.
  static double heightOf(Layout layout, {bool withRole = true}) =>
      avatarOf(layout) + (layout.isLarge ? layout.tv(withRole ? 136 : 76) : (withRole ? 76 : 44));

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = avatarOf(layout);
    final large = layout.isLarge;

    return VxFocusable(
      borderRadius: large ? layout.tv(20) : 12,
      semanticLabel: role == null ? person.name : '${person.name}, $role',
      onPressed: () => context.push(personPath(person.id)),
      child: SizedBox(
        width: widthOf(layout),
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: SizedBox.square(
                  dimension: size,
                  child: NetImage(
                    url: person.profileUrl,
                    seed: person.id,
                    fallback: Center(child: Text(person.initials, style: VxText.title(size * 0.3))),
                  ),
                ),
              ),
              SizedBox(height: large ? layout.tv(12) : 8),
              Text(
                person.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: VxText.body(large ? layout.tv(24) : 13, weight: FontWeight.w600, height: 1.2),
              ),
              if (role != null) ...[
                SizedBox(height: large ? layout.tv(4) : 2),
                Text(
                  role!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: VxText.body(large ? layout.tv(20) : 12, color: VxColors.textSecondary, height: 1.2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid layout for title cards, by screen and format.
SliverGridDelegate posterGridDelegate(Layout layout, PosterFormat format) {
  final gap = layout.isLarge ? layout.tv(28) : 10.0;
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: rowCardWidth(layout, format) * 1.15,
    childAspectRatio: format == PosterFormat.portrait ? 2 / 3 : 16 / 9,
    crossAxisSpacing: gap,
    mainAxisSpacing: gap,
  );
}

/// Grid of title cards (Ma liste, genres), following the profile's poster format.
class PosterGrid extends ConsumerWidget {
  const PosterGrid({super.key, required this.items, this.padding, this.alwaysScrollable = false});

  final List<MediaItem> items;
  final EdgeInsetsGeometry? padding;
  final bool alwaysScrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final format = posterFormatOf(ref);
    return GridView.builder(
      physics: alwaysScrollable ? const AlwaysScrollableScrollPhysics() : null,
      padding: padding ?? EdgeInsets.all(layout.gutter),
      gridDelegate: posterGridDelegate(layout, format),
      itemCount: items.length,
      itemBuilder: (context, i) => LayoutBuilder(
        builder: (context, c) =>
            PosterCard(item: items[i], width: c.maxWidth, format: format, autofocus: i == 0 && layout.isLarge),
      ),
    );
  }
}

/// Long press menu: Ma liste, marquer vu / non vu.
Future<void> showTitleMenu(BuildContext context, MediaItem item) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: VxColors.surface,
  showDragHandle: true,
  builder: (sheetContext) => Consumer(
    builder: (sheetContext, ref, _) {
      final state = ref.watch(libraryProvider).value?.forItem(item);
      final favorite = state?.isFavorite ?? false;
      final watched = state?.isWatched ?? false;
      void then(Future<void> Function(BuildContext, MediaItem) action) {
        Navigator.of(sheetContext).pop();
        action(context, item);
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(item.title, style: VxText.title(20)),
            ),
            _MenuTile(
              icon: favorite ? Icons.bookmark_remove_rounded : Icons.bookmark_add_outlined,
              label: favorite ? 'Retirer de ma liste' : 'Ajouter à ma liste',
              autofocus: true,
              onTap: () => then(toggleFavorite),
            ),
            if (item.type == MediaType.movie)
              _MenuTile(
                icon: watched ? Icons.remove_done_rounded : Icons.check_circle_outline_rounded,
                label: watched ? 'Marquer comme non vu' : 'Marquer comme vu',
                onTap: () => then(toggleWatched),
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  ),
);

/// Long press menu of a "Continuer à regarder" card.
Future<void> showResumeMenu(BuildContext context, ProfileItem item) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: VxColors.surface,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(item.title, style: VxText.title(20)),
        ),
        _MenuTile(
          icon: Icons.remove_circle_outline_rounded,
          label: 'Retirer de « Continuer à regarder »',
          autofocus: true,
          onTap: () async {
            Navigator.of(sheetContext).pop();
            final container = ProviderScope.containerOf(context, listen: false);
            try {
              await container.read(libraryProvider.notifier).removeFromContinueWatching(item);
              if (context.mounted) {
                showVxSnack(context, 'Retiré de « Continuer à regarder »', icon: Icons.remove_circle_outline_rounded);
              }
            } catch (e) {
              if (context.mounted) showVxSnack(context, '$e', icon: Icons.error_outline_rounded);
            }
          },
        ),
        const SizedBox(height: 12),
      ],
    ),
  ),
);

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.autofocus = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => ListTile(
    autofocus: autofocus,
    leading: Icon(icon, color: VxColors.text),
    title: Text(label, style: VxText.body(16, weight: FontWeight.w500)),
    onTap: onTap,
    minTileHeight: 56,
    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
  );
}
