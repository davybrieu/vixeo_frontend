import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../library/library.dart';
import 'models.dart';

String titlePath(MediaType type, int id) => '/titre/${type.name}/$id';

/// Poster 2:3 with the title as fallback when there is no image.
class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.item, required this.width, this.onFocused, this.autofocus = false});

  final MediaItem item;
  final double width;
  final VoidCallback? onFocused;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final radius = width * 0.086;
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: radius,
      semanticLabel: '${item.title}, ${item.type.label.toLowerCase()}${item.year != null ? ', ${item.year}' : ''}',
      onFocused: onFocused,
      onPressed: () => context.push(titlePath(item.type, item.id)),
      onLongPress: () => showTitleMenu(context, item),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: width * 1.5,
          child: NetImage(
            url: item.posterUrl,
            seed: item.id,
            fallback: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.all(width * 0.08),
                child: Text(item.title, maxLines: 3, style: VxText.title(width * 0.12)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal row of posters, with its title.
class PosterRow extends StatelessWidget {
  const PosterRow({super.key, required this.title, required this.items, this.onFocused});

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem item)? onFocused;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final width = layout.isLarge ? layout.tv(220) : (layout.isPhone ? 116.0 : 140.0);
    final gap = layout.isLarge ? layout.tv(28) : 10.0;
    // Room for the focus zoom on TV.
    final vPad = layout.isLarge ? layout.tv(16) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        FocusTraversalGroup(
          child: SizedBox(
            height: width * 1.5 + vPad * 2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: layout.gutter, vertical: vPad),
              itemCount: items.length,
              separatorBuilder: (_, _) => SizedBox(width: gap),
              itemBuilder: (context, i) => PosterCard(
                item: items[i],
                width: width,
                onFocused: onFocused == null ? null : () => onFocused!(items[i]),
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
  const ResumeCard({super.key, required this.item, required this.width, this.autofocus = false});

  final ProfileItem item;
  final double width;
  final bool autofocus;

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

/// Grid of posters (Ma liste, genres, search results).
class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.items, this.padding});

  final List<MediaItem> items;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final itemWidth = layout.isLarge ? layout.tv(220) : 116.0;
    return GridView.builder(
      padding: padding ?? EdgeInsets.all(layout.gutter),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: itemWidth * 1.15,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: layout.isLarge ? layout.tv(28) : 10,
        mainAxisSpacing: layout.isLarge ? layout.tv(28) : 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => LayoutBuilder(
        builder: (context, c) => PosterCard(item: items[i], width: c.maxWidth, autofocus: i == 0 && layout.isLarge),
      ),
    );
  }
}

/// Long press menu: Ma liste, marquer vu.
Future<void> showTitleMenu(BuildContext context, MediaItem item) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: VxColors.surface,
  showDragHandle: true,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      final state = ref.watch(libraryProvider).value?.forItem(item);
      final library = ref.read(libraryProvider.notifier);
      final favorite = state?.isFavorite ?? false;
      final watched = state?.isWatched ?? false;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(item.title, style: VxText.title(20)),
            ),
            _MenuTile(
              icon: favorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              label: favorite ? 'Retirer de ma liste' : 'Ajouter à ma liste',
              autofocus: true,
              onTap: () => _run(context, () => library.setFavorite(item, !favorite)),
            ),
            if (item.type == MediaType.movie)
              _MenuTile(
                icon: watched ? Icons.remove_done_rounded : Icons.check_circle_outline_rounded,
                label: watched ? 'Marquer comme non vu' : 'Marquer comme vu',
                onTap: () => _run(context, () => library.setWatched(item, !watched)),
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
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      return SafeArea(
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
              onTap: () => _run(context, () => ref.read(libraryProvider.notifier).removeFromContinueWatching(item)),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  ),
);

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).pop();
  try {
    await action();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

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
