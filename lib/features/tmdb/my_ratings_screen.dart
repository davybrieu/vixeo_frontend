import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';
import '../catalog/widgets.dart';
import '../search/filter_bar.dart';
import 'rating_dialog.dart';
import 'tmdb.dart';

/// "Mes notes" (`/profil/notes`): the ratings of the profile's TMDb account, by type, the most
/// recent first. Each one opens its page, and can be changed or removed (saved on TMDb).
class MyRatingsScreen extends ConsumerStatefulWidget {
  const MyRatingsScreen({super.key});

  @override
  ConsumerState<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends ConsumerState<MyRatingsScreen> {
  RatedType _type = RatedType.movie;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final account = ref.watch(tmdbAccountProvider);
    final canPop = GoRouter.maybeOf(context)?.canPop() ?? false;

    Widget body;
    if (!account.hasValue) {
      body = AsyncView(
        value: account,
        onRetry: () => ref.invalidate(tmdbAccountProvider),
        data: (_) => const SizedBox(),
      );
    } else if (!account.value!.linked) {
      body = EmptyState(
        icon: Icons.star_outline_rounded,
        title: 'Aucun compte TMDb lié',
        message: 'Liez votre compte TMDb pour noter films, séries et épisodes, et retrouver vos notes ici.',
        action: VxButton(
          label: 'Lier mon compte TMDb',
          icon: Icons.link_rounded,
          autofocus: true,
          onPressed: () => context.push('/profil/tmdb'),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FocusTraversalGroup(
            child: Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, 4 * s, layout.gutter, 12 * s),
              child: Wrap(
                spacing: 8 * s,
                runSpacing: 8 * s,
                children: [
                  for (final type in RatedType.values)
                    FilterChipButton(
                      label: type.label,
                      selected: type == _type,
                      semanticLabel: type == _type ? '${type.label}, sélectionné' : type.label,
                      onPressed: () => setState(() => _type = type),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _RatingsList(key: ValueKey(_type), type: _type),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: VxColors.background,
        title: Row(
          children: [
            Text('Mes notes', style: VxText.title(20 * s)),
            SizedBox(width: 12 * s),
            TmdbLogo(height: 12 * s),
          ],
        ),
        leading: canPop
            ? null
            : IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/profil'),
              ),
      ),
      body: body,
    );
  }
}

class _RatingsList extends ConsumerWidget {
  const _RatingsList({super.key, required this.type});

  final RatedType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final ratings = ref.watch(myRatingsProvider(type));

    return AsyncView(
      value: ratings,
      onRetry: () => ref.invalidate(myRatingsProvider(type)),
      data: (list) {
        if (list.items.isEmpty) {
          return EmptyState(
            icon: Icons.star_outline_rounded,
            title: 'Aucune note',
            message: switch (type) {
              RatedType.movie => 'Notez un film depuis sa fiche : il apparaîtra ici.',
              RatedType.tv => 'Notez une série depuis sa fiche : elle apparaîtra ici.',
              RatedType.episode => 'Notez un épisode depuis la fiche de sa série : il apparaîtra ici.',
            },
          );
        }
        // Aligned with the tabs, at a readable width.
        return Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 900 * uiScale(context)),
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 48),
              itemCount: list.items.length + (list.hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= list.items.length) {
                  // The end of the list is in view: next page.
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => ref.read(myRatingsProvider(type).notifier).loadMore(),
                  );
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return _RatedRow(item: list.items[i]);
              },
            ),
          ),
        );
      },
    );
  }
}

/// One rating: image, title, "Ma note", then Modifier / Supprimer (TV: → from the row).
class _RatedRow extends StatelessWidget {
  const _RatedRow({required this.item});

  final RatedItem item;

  Future<void> _remove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette note ?'),
        content: Text(
          'Votre note de « ${item.label} » sera aussi supprimée sur TMDb.',
          style: VxText.body(15, color: VxColors.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          VxButton(
            label: 'Supprimer',
            kind: VxButtonKind.danger,
            autofocus: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ProviderScope.containerOf(context, listen: false).read(tmdbRatingsProvider).remove(item.target);
      showVxSnackOn(messenger, 'Note supprimée', icon: Icons.star_outline_rounded);
    } on ApiException catch (e) {
      showVxSnackOn(messenger, e.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final episode = item.type == RatedType.episode;
    final subtitle = episode
        ? 'Saison ${item.seasonNumber}, épisode ${item.episodeNumber}${item.episodeName == null ? '' : ' · ${item.episodeName}'}'
        : (item.year?.toString() ?? '');

    return Padding(
      padding: EdgeInsets.only(bottom: 12 * s),
      child: Row(
        children: [
          Expanded(
            child: VxFocusable(
              borderRadius: 12 * s,
              semanticLabel: '${item.label}, ma note : ${formatScore(item.value)} sur 10',
              onPressed: () => context.push('/titre/${item.mediaType.name}/${item.id}'),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8 * s),
                    child: SizedBox(
                      width: episode ? 112 * s : 56 * s,
                      height: 84 * s * (episode ? 0.75 : 1),
                      child: NetImage(
                        url: episode ? (item.stillUrl ?? item.backdropUrl) : item.posterUrl,
                        seed: item.id,
                      ),
                    ),
                  ),
                  SizedBox(width: 14 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VxText.body(15 * s, weight: FontWeight.w600, height: 1.3),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: VxText.body(13 * s, color: VxColors.textSecondary),
                          ),
                        SizedBox(height: 4 * s),
                        Row(
                          children: [
                            Icon(Icons.star_rounded, size: 16 * s, color: VxColors.accent),
                            SizedBox(width: 4 * s),
                            Flexible(
                              child: Text(
                                'Ma note : ${formatScore(item.value)}/10',
                                overflow: TextOverflow.ellipsis,
                                style: VxText.body(13 * s, color: VxColors.accent, weight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 8 * s),
          VxIconAction(
            dense: true,
            icon: Icons.edit_rounded,
            label: 'Modifier ma note de ${item.label}',
            onPressed: () => editRating(
              context,
              target: item.target,
              name: episode ? (item.episodeName ?? item.title) : item.title,
              subtitle: episode ? '${item.title} · Saison ${item.seasonNumber}, épisode ${item.episodeNumber}' : null,
              current: item.value,
            ),
          ),
          SizedBox(width: 8 * s),
          VxIconAction(
            dense: true,
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer ma note de ${item.label}',
            onPressed: () => _remove(context),
          ),
        ],
      ),
    );
  }
}
