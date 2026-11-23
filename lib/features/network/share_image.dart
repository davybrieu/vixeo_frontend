import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/share.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../tmdb/rating_form.dart' show StarRow;
import '../tmdb/tmdb.dart' show formatScore;
import 'network.dart';

// « Partager en image » (developer's request, 23/11/2026): a review, a top 10 or the year's review
// drawn as a picture in the story format (9:16), to post on Instagram, WhatsApp… The page shows it
// as it will be; « Partager » takes a picture of it (the images are loaded since they are shown)
// and opens Android's share sheet; on Windows, the picture goes to the Downloads folder.

/// What a story shows, and the name of its file.
class StoryContent {
  const StoryContent._(this.name, this.text, this.builder);

  factory StoryContent.review(SocialReview review) => StoryContent._(
    'vixeo-avis-${review.id}',
    'Mon avis sur ${review.item.label} sur Vixeo',
    (_) => _ReviewStory(review: review),
  );

  factory StoryContent.list(SocialList list) => StoryContent._(
    'vixeo-liste-${list.id}',
    '${list.title} sur Vixeo',
    (_) => _ListStory(list: list),
  );

  factory StoryContent.year(YearStats stats, String name) => StoryContent._(
    'vixeo-bilan-${stats.year}',
    'Mon année ${stats.year} sur Vixeo',
    (_) => _YearStory(stats: stats, name: name),
  );

  final String name;

  /// Sent with the image.
  final String text;
  final WidgetBuilder builder;
}

/// Opens the story [content] over everything, with « Partager ».
Future<void> openStory(BuildContext context, StoryContent content) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => StoryScreen(content: content)),
);

/// Size of a story, in logical pixels (×3 in the picture: 1080 × 1920).
const _storySize = Size(360, 640);

class StoryScreen extends ConsumerStatefulWidget {
  const StoryScreen({super.key, required this.content});

  final StoryContent content;

  @override
  ConsumerState<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends ConsumerState<StoryScreen> {
  final _story = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    try {
      final boundary = _story.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw const FileSystemException('PNG');
      final windows = Platform.isWindows;
      final folder = windows
          ? await getDownloadsDirectory() ?? await getTemporaryDirectory()
          : Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}shared');
      await folder.create(recursive: true);
      final file = File('${folder.path}${Platform.pathSeparator}${widget.content.name}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      if (windows) {
        showVxSnackOn(messenger, 'Image enregistrée dans « ${folder.path} »', icon: Icons.download_done_rounded);
        return;
      }
      final opened = await ref.read(linkSharerProvider).shareImage(file.path, text: widget.content.text);
      if (!opened) showVxSnackOn(messenger, 'Impossible d’ouvrir le partage.', icon: Icons.error_outline_rounded);
    } catch (_) {
      showVxSnackOn(messenger, 'Impossible de créer l’image.', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Scaffold(
      backgroundColor: VxColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(layout.space(VxSpace.s)),
              child: Row(
                children: [
                  VxIconAction(
                    icon: Icons.close_rounded,
                    label: 'Fermer',
                    dense: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  VxButton(
                    label: Platform.isWindows ? 'Enregistrer l’image' : 'Partager',
                    icon: Platform.isWindows ? Icons.download_rounded : Icons.ios_share_rounded,
                    dense: true,
                    autofocus: true,
                    loading: _sharing,
                    onPressed: _share,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(layout.space(VxSpace.m)),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _story,
                    child: SizedBox.fromSize(size: _storySize, child: Builder(builder: widget.content.builder)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame of every story: the colours of Vixeo, the logo above, the site below.
class _StoryFrame extends StatelessWidget {
  const _StoryFrame({required this.child, this.backdrop});

  final Widget child;
  final String? backdrop;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0E3B25), VxColors.background, VxColors.background],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (backdrop != null)
          Opacity(opacity: 0.18, child: NetImage(url: backdrop)),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const VxLogo(size: 20),
              const SizedBox(height: 18),
              Expanded(child: child),
              Center(child: Text('vixeo.app', style: VxText.body(11, color: VxColors.textSecondary))),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _poster(String? url, double width, {int seed = 0}) => ClipRRect(
  borderRadius: BorderRadius.circular(width * 0.06),
  child: SizedBox(width: width, height: width * 1.5, child: NetImage(url: url, seed: seed)),
);

class _ReviewStory extends StatelessWidget {
  const _ReviewStory({required this.review});

  final SocialReview review;

  @override
  Widget build(BuildContext context) {
    final item = review.item;
    final comment = item.comment?.trim() ?? '';
    return _StoryFrame(
      backdrop: item.backdropUrl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _poster(item.posterUrl, 170, seed: item.id),
          const SizedBox(height: 16),
          Text(item.label, textAlign: TextAlign.center, maxLines: 2, style: VxText.title(22)),
          Text(item.subtitle, style: VxText.body(12, color: VxColors.textSecondary)),
          const SizedBox(height: 12),
          StarRow(value: item.value, size: 20),
          const SizedBox(height: 4),
          Text('${formatScore(item.value)}/10', style: VxText.title(26, color: VxColors.accent)),
          const SizedBox(height: 12),
          if (comment.isNotEmpty)
            Expanded(
              child: Text(
                review.spoilers ? 'Avis avec spoilers : à lire sur Vixeo.' : '« $comment »',
                textAlign: TextAlign.center,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: VxText.body(13, color: VxColors.textSoft),
              ),
            )
          else
            const Spacer(),
          Text('@${review.author.username}', style: VxText.body(13, weight: FontWeight.w700)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _ListStory extends StatelessWidget {
  const _ListStory({required this.list});

  final SocialList list;

  @override
  Widget build(BuildContext context) {
    final titles = (list.items ?? const []).take(list.kind == ListKind.top ? 10 : 9).toList();
    final top = list.kind == ListKind.top;
    return _StoryFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (top) const VxBadge('TOP 10', accent: true),
          const SizedBox(height: 6),
          Text(list.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: VxText.title(22)),
          Text('par @${list.author.username}', style: VxText.body(12, color: VxColors.textSecondary)),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.count(
              crossAxisCount: top ? 4 : 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2 / 3,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final (i, title) in titles.indexed)
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(6), child: NetImage(url: title.posterUrl, seed: title.id)),
                      if (top)
                        Positioned(
                          left: 3,
                          top: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: VxColors.accent, borderRadius: BorderRadius.circular(5)),
                            child: Text('${i + 1}', style: VxText.title(11, color: VxColors.onAccent)),
                          ),
                        ),
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

class _YearStory extends StatelessWidget {
  const _YearStory({required this.stats, required this.name});

  final YearStats stats;
  final String name;

  @override
  Widget build(BuildContext context) {
    Widget number(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: VxText.title(28, color: VxColors.accent)),
          Text(label, textAlign: TextAlign.center, style: VxText.body(11, color: VxColors.textSecondary)),
        ],
      ),
    );
    return _StoryFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mon année ${stats.year}', style: VxText.title(26)),
          Text(name, style: VxText.body(12, color: VxColors.textSecondary)),
          const SizedBox(height: 18),
          Row(
            children: [
              number('${stats.moviesCount}', stats.moviesCount > 1 ? 'films' : 'film'),
              number('${stats.episodesCount}', stats.episodesCount > 1 ? 'épisodes' : 'épisode'),
              number('${stats.hours}', stats.hours > 1 ? 'heures' : 'heure'),
            ],
          ),
          const SizedBox(height: 18),
          if (stats.genres.isNotEmpty) ...[
            Text('Mes genres', style: VxText.body(12, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final g in stats.genres.take(4)) VxBadge(g.name, outlined: true, fontSize: 11)],
            ),
            const SizedBox(height: 18),
          ],
          if (stats.bestRated.isNotEmpty) ...[
            Text('Mes mieux notés', style: VxText.body(12, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (i, best) in stats.bestRated.take(4).indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: NetImage(url: best.title.posterUrl, seed: best.title.id),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${formatScore(best.value)}/10', style: VxText.body(11, color: VxColors.accent, weight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
          const Spacer(),
          if (stats.topShow != null)
            Text(
              'Ma série de l’année : ${stats.topShow!.title}',
              maxLines: 2,
              style: VxText.body(12, color: VxColors.textSoft),
            ),
        ],
      ),
    );
  }
}

/// Used by the pages that offer « Partager en image » (not on a TV: no share sheet there).
bool get canShareImages => !DeviceInfo.isTv;
