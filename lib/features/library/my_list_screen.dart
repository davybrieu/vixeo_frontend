import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';
import 'library.dart';

/// "Ma liste": the active profile's favorites (synced between devices).
class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  MediaType? _filter;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final library = ref.watch(libraryProvider);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 16 * s, layout.gutter, 12 * s),
            child: Row(
              children: [
                Expanded(child: Text('Ma liste', style: VxText.title(28 * s))),
                for (final (label, value) in [('Tout', null), ('Films', MediaType.movie), ('Séries', MediaType.tv)])
                  Padding(
                    padding: EdgeInsets.only(left: 8 * s),
                    child: VxFocusable(
                      borderRadius: 18 * s,
                      semanticLabel: label,
                      onPressed: () => setState(() => _filter = value),
                      child: Container(
                        height: 36 * s,
                        padding: EdgeInsets.symmetric(horizontal: 14 * s),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _filter == value ? VxColors.accent.withValues(alpha: 0.14) : Colors.transparent,
                          border: _filter == value ? null : Border.all(color: VxColors.lineStrong),
                          borderRadius: BorderRadius.circular(18 * s),
                        ),
                        child: Text(
                          label,
                          style: VxText.body(
                            14 * s,
                            weight: FontWeight.w600,
                            color: _filter == value ? VxColors.accent : VxColors.text,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: library,
              onRetry: () => ref.invalidate(libraryProvider),
              data: (state) {
                final items = [
                  for (final fav in state.favorites)
                    if (fav.tmdbTitle case final t? when _filter == null || t.type == _filter)
                      MediaItem(
                        id: t.id,
                        type: t.type,
                        title: fav.title,
                        year: fav.year,
                        posterUrl: fav.posterUrl,
                        backdropUrl: fav.backdropUrl,
                      ),
                ];
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Votre liste est vide',
                    message: 'Ajoutez des films et des séries avec « Ma liste » pour les retrouver ici, sur tous vos écrans.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                  child: PosterGrid(items: items),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
