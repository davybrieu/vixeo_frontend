import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focus_navigation.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../../core/widgets/tabs.dart';
import 'artwork.dart';
import 'models.dart';
import 'widgets.dart';

/// « Affiches, arrière-plans, logos » of a title (`/titre/:type/:id/images?sorte=…`; developer's
/// request, 25/11/2026, after another film app; opened by the « ⋮ » of the title page: « Changer
/// l’affiche », « … l’arrière-plan », « … le logo », each on its tab): three tabs, « Par défaut »
/// (TMDb's) first, then TMDb's images; the chosen one has a green ring. A tap keeps it at once, and
/// every list, search and title page then shows it for this profile.
class ArtworkScreen extends ConsumerStatefulWidget {
  const ArtworkScreen({super.key, required this.type, required this.id, this.initialKind = ArtworkKind.poster});

  final MediaType type;
  final int id;

  /// The tab shown first.
  final ArtworkKind initialKind;

  static String location(MediaType type, int id, {ArtworkKind kind = ArtworkKind.poster}) =>
      '/titre/${type.name}/$id/images${kind == ArtworkKind.poster ? '' : '?sorte=${kind.slug}'}';

  @override
  ConsumerState<ArtworkScreen> createState() => _ArtworkScreenState();
}

class _ArtworkScreenState extends ConsumerState<ArtworkScreen> {
  late var _kind = widget.initialKind;

  /// The choices made on this page (the server's until then): shown at once.
  final _chosen = <ArtworkKind, String?>{};

  Future<void> _choose(ArtworkKind kind, String? path, TitleImages images) async {
    final before = _chosen.containsKey(kind) ? _chosen[kind] : images.chosen[kind];
    if (before == path) return;
    setState(() => _chosen[kind] = path);
    try {
      await chooseTitleImage(ref, widget.type, widget.id, kind, path);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _chosen[kind] = before);
      showVxSnack(context, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final images = ref.watch(titleImagesProvider((widget.type, widget.id)));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VxPageHeader(title: _kind.label, back: true),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: VxTabs(
                labels: [for (final kind in ArtworkKind.values) kind.label],
                selected: _kind.index,
                autofocus: true,
                onSelected: (i) => setState(() => _kind = ArtworkKind.values[i]),
              ),
            ),
            SizedBox(height: layout.sectionGap),
            Expanded(
              child: AsyncView(
                value: images,
                onRetry: () => ref.invalidate(titleImagesProvider((widget.type, widget.id))),
                data: (images) => _ArtworkGrid(
                  key: ValueKey(_kind),
                  kind: _kind,
                  images: images,
                  chosen: _chosen.containsKey(_kind) ? _chosen[_kind] : images.chosen[_kind],
                  onChoose: (path) => _choose(_kind, path, images),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Par défaut », then TMDb's images of one kind.
class _ArtworkGrid extends StatelessWidget {
  const _ArtworkGrid({
    super.key,
    required this.kind,
    required this.images,
    required this.chosen,
    required this.onChoose,
  });

  final ArtworkKind kind;
  final TitleImages images;

  /// The chosen path; null: TMDb's (« Par défaut »).
  final String? chosen;
  final ValueChanged<String?> onChoose;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final fallback = images.defaults[kind];
    // « Par défaut » shows TMDb's image; the same image is not offered twice.
    final list = [for (final image in images.images[kind]!) if (image.path != fallback?.path) image];
    final aspectRatio = kind == ArtworkKind.poster ? 2 / 3 : 16 / 9;
    final extent = kind == ArtworkKind.poster
        ? rowCardWidth(layout) * 1.15
        : (layout.isLarge ? layout.tv(420) : (layout.isPhone ? 190.0 : 240.0));
    final captionHeight = MediaQuery.textScalerOf(context).scale(layout.isLarge ? layout.tv(22) : 13) * 1.4 + 8;
    final gap = layout.cardGap;

    if (fallback == null && list.isEmpty) {
      return EmptyState(
        icon: Icons.image_not_supported_outlined,
        title: 'Aucune image',
        message: 'TMDb n’a pas d’image de ce type pour ce titre.',
      );
    }

    return FocusTraversalGroup(
      policy: vxTraversalPolicy,
      child: GridView.builder(
        padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, pageBottomPadding(context)),
        // Room under each image for « Par défaut » (the same on every tile: the rows line up).
        gridDelegate: imageGridDelegate(
          maxCrossAxisExtent: extent,
          imageAspectRatio: aspectRatio,
          spacing: gap,
          captionHeight: captionHeight,
        ),
        itemCount: list.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return _ArtworkTile(
              kind: kind,
              url: fallback?.url,
              label: 'Par défaut',
              selected: chosen == null,
              captionHeight: captionHeight,
              onPressed: () => onChoose(null),
            );
          }
          final image = list[i - 1];
          return _ArtworkTile(
            kind: kind,
            url: image.url,
            semanticLabel: '${kind.one} $i',
            selected: chosen == image.path,
            captionHeight: captionHeight,
            onPressed: () => onChoose(image.path),
          );
        },
      ),
    );
  }
}

/// One image: a green ring when chosen; [label] under it (« Par défaut »).
class _ArtworkTile extends StatelessWidget {
  const _ArtworkTile({
    required this.kind,
    required this.url,
    required this.selected,
    required this.captionHeight,
    required this.onPressed,
    this.label,
    this.semanticLabel,
  });

  final ArtworkKind kind;
  final String? url;
  final bool selected;
  final double captionHeight;
  final VoidCallback onPressed;
  final String? label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final radius = kind == ArtworkKind.poster ? 14.0 : 12.0;
    final ring = layout.isLarge ? layout.tv(5) : 3.0;
    final name = label ?? semanticLabel ?? kind.one;
    final image = kind == ArtworkKind.logo
        // A logo is transparent: on the page's dark surface, whole.
        ? ColoredBox(
            color: VxColors.surfaceHigh,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: NetImage(url: url, seed: 1, fit: BoxFit.contain, fallback: const SizedBox()),
            ),
          )
        : NetImage(url: url, seed: url.hashCode, fallback: const Center(child: Icon(Icons.image_outlined)));

    return VxFocusable(
      onPressed: onPressed,
      borderRadius: radius,
      semanticLabel: selected ? '$name, choisi' : name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: EdgeInsets.all(selected ? ring : 0),
              decoration: BoxDecoration(
                color: selected ? VxColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(radius + (selected ? ring : 0)),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: image),
            ),
          ),
          SizedBox(
            height: captionHeight,
            child: label == null
                ? null
                // Read with the tile's label already.
                : ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        label!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(
                          layout.isLarge ? layout.tv(22) : 13,
                          weight: FontWeight.w600,
                          color: VxColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
