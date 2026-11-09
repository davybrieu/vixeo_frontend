import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../search/filter_bar.dart';
import 'rating_dialog.dart';
import 'review_screen.dart';
import 'tmdb.dart';

/// "Mes avis" (`/avis`, in the main navigation): the profile's ratings of its TMDb account and its
/// comments, the most recent first. Filters (Tout by default, Films, Séries, Épisodes) and a search
/// bar as on Ma liste. Each review shows its stars and opens « Mon avis » (`ReviewScreen`), where it
/// is changed or removed: no button on the list.
class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key});

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  final _search = TextEditingController();
  String _query = '';

  /// Null: every type ("Tout").
  RatedType? _type;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final account = ref.watch(tmdbAccountProvider);

    Widget body;
    if (!account.hasValue) {
      body = AsyncView(
        value: account,
        onRetry: () => ref.invalidate(tmdbAccountProvider),
        data: (_) => const SizedBox(),
      );
    } else if (!account.value!.linked) {
      body = EmptyState(
        icon: Icons.rate_review_outlined,
        title: 'Aucun compte TMDb lié',
        message: 'Liez votre compte TMDb dans Paramètres › Connexions pour noter films, séries et épisodes.',
        action: VxButton(
          label: 'Lier mon compte TMDb',
          icon: Icons.link_rounded,
          autofocus: true,
          onPressed: () => context.push('/profil/connexions'),
        ),
      );
    } else {
      body = _ReviewsList(type: _type, query: _query);
    }

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VxPageHeader(
            title: 'Mes avis',
            search: VxSearchField(
              controller: _search,
              autofocus: !layout.isPhone,
              fontSize: layout.size(16, tv: 24),
              hintText: 'Titre, épisode, commentaire…',
              onChanged: (value) => setState(() => _query = value),
              onClear: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
            filters: FilterBar(
              child: FilterBar.chips(layout, [
                for (final type in <RatedType?>[null, ...RatedType.values])
                  FilterChipButton(
                    label: type?.label ?? 'Tout',
                    selected: type == _type,
                    semanticLabel: '${type?.label ?? 'Tout'}${type == _type ? ', sélectionné' : ''}',
                    onPressed: () => setState(() => _type = type),
                  ),
              ]),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _ReviewsList extends ConsumerWidget {
  const _ReviewsList({required this.type, required this.query});

  final RatedType? type;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final reviews = ref.watch(reviewsProvider);

    return AsyncView(
      value: reviews,
      onRetry: () => ref.invalidate(reviewsProvider),
      data: (all) {
        final items = [
          for (final item in all)
            if ((type == null || item.type == type) && item.matches(query)) item,
        ];
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.rate_review_outlined,
            title: all.isEmpty ? 'Aucun avis' : 'Aucun résultat',
            message: all.isEmpty
                ? 'Notez un film, une série ou un épisode depuis sa fiche : votre avis apparaîtra ici.'
                : 'Aucun de vos avis ne correspond à cette recherche ou à ce filtre.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(reviewsProvider);
            await ref.read(reviewsProvider.future);
          },
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.size(900, tv: 1500)),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: pageContentPadding(context),
                itemCount: items.length,
                separatorBuilder: (_, _) => SizedBox(height: layout.space(VxSpace.s)),
                itemBuilder: (_, i) => ReviewRow(item: items[i]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One review: image, title, its stars and the comment. Opens « Mon avis » (`ReviewScreen`), where
/// it is changed or removed.
class ReviewRow extends StatelessWidget {
  const ReviewRow({super.key, required this.item});

  final RatedItem item;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final episode = item.type == RatedType.episode;
    final caption = layout.captionSize;
    final imageWidth = layout.size(episode ? 112 : 64, tv: episode ? 200 : 112);
    final imageHeight = episode ? imageWidth * 9 / 16 : imageWidth * 1.5;

    return VxFocusable(
      borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
      semanticLabel:
          '${item.label}, ma note : ${formatScore(item.value)} sur 10${item.comment == null ? '' : ', ${item.comment}'}',
      onPressed: () => context.push(ReviewScreen.location(item.target)),
      child: Padding(
        padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(VxRadius.poster),
              child: SizedBox(
                width: imageWidth,
                height: imageHeight,
                child: NetImage(url: episode ? (item.stillUrl ?? item.backdropUrl) : item.posterUrl, seed: item.id),
              ),
            ),
            SizedBox(width: layout.space(VxSpace.s)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(layout.size(16, tv: 24), weight: FontWeight.w600, height: 1.3),
                  ),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VxText.body(caption, color: VxColors.textSecondary),
                  ),
                  SizedBox(height: layout.space(VxSpace.xxs)),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: layout.space(VxSpace.xs),
                    children: [
                      StarRow(value: item.value, size: caption * 1.2),
                      Text(
                        '${formatScore(item.value)}/10',
                        style: VxText.body(caption, color: VxColors.accent, weight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (item.comment != null) ...[
                    SizedBox(height: layout.space(VxSpace.xxs)),
                    Text(
                      '« ${item.comment} »',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: VxText.body(layout.bodySize, color: VxColors.textSoft),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: layout.space(VxSpace.xs)),
            Icon(Icons.chevron_right_rounded, size: layout.size(22, tv: 34), color: VxColors.textMuted),
          ],
        ),
      ),
    );
  }
}
