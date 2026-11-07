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
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
            padding: EdgeInsets.fromLTRB(layout.gutter, 16 * s, layout.gutter, 4 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ma liste', style: VxText.title(28 * s)),
                SizedBox(height: 16 * s),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: layout.isPhone ? double.infinity : 720 * s),
                  child: ValueListenableBuilder(
                    valueListenable: _searchController,
                    builder: (_, value, _) => TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      style: VxText.body(16 * s),
                      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Films, séries…',
                        filled: true,
                        fillColor: VxColors.background.withValues(alpha: 0.6),
                        prefixIcon: const Icon(Icons.search_rounded, color: VxColors.textSecondary),
                        suffixIcon: value.text.isEmpty ? null : IconButton(
                          tooltip: 'Effacer',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () { _searchController.clear(); setState(() => _query = ''); },
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: VxColors.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: VxColors.line)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: VxColors.accent, width: 2)),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12 * s),
                Row(
                  children: [
                    for (final (label, value) in [('Tout', null), ('Films', MediaType.movie), ('Séries', MediaType.tv)])
                      Padding(
                        padding: EdgeInsets.only(right: 8 * s),
                        child: VxFocusable(
                          borderRadius: 18 * s,
                          semanticLabel: label,
                          onPressed: () => setState(() => _filter = value),
                          child: Container(
                            height: 34 * s,
                            padding: EdgeInsets.symmetric(horizontal: 13 * s),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _filter == value ? VxColors.accent.withValues(alpha: 0.14) : Colors.transparent,
                              border: _filter == value ? null : Border.all(color: VxColors.lineStrong),
                              borderRadius: BorderRadius.circular(18 * s),
                            ),
                            child: Text(
                              label,
                              style: VxText.body(
                                13 * s,
                                weight: FontWeight.w600,
                                color: _filter == value ? VxColors.accent : VxColors.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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
                    if (fav.tmdbTitle case final t? when (_filter == null || t.type == _filter) && (_query.isEmpty || fav.title.toLowerCase().contains(_query)))
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
                  return EmptyState(
                    icon: Icons.bookmark_border_rounded,
                    title: _query.isNotEmpty ? 'Aucun résultat' : 'Votre liste est vide',
                    message: _query.isNotEmpty
                        ? 'Aucun titre de votre liste ne correspond à « ${_searchController.text} ».'
                        : 'Ajoutez des films et des séries avec « Ma liste » pour les retrouver ici, sur tous vos écrans.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(bottom: 20 * s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.all(layout.gutter),
                          gridDelegate: posterGridDelegate(layout, posterFormatOf(ref)),
                          itemCount: items.length,
                          itemBuilder: (context, i) => LayoutBuilder(
                            builder: (context, constraints) => PosterCard(
                              item: items[i],
                              width: constraints.maxWidth,
                              format: posterFormatOf(ref),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
