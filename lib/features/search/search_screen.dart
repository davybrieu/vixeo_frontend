import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../catalog/widgets.dart';

/// Recent searches of this app session (not synced yet).
final recentSearchesProvider = NotifierProvider<RecentSearches, List<String>>(RecentSearches.new);

class RecentSearches extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void add(String query) => state = [query, ...state.where((q) => q != query)].take(8).toList();

  void remove(String query) => state = state.where((q) => q != query).toList();

  void clear() => state = const [];
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = value.trim();
      if (q.length >= 2) ref.read(recentSearchesProvider.notifier).add(q);
      setState(() => _query = q.length >= 2 ? q : '');
    });
  }

  void _use(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    setState(() => _query = query);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(layout.gutter, 16 * s, layout.gutter, 16 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recherche', style: VxText.title(28 * s)),
                SizedBox(height: 16 * s),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: layout.isPhone ? double.infinity : 720 * s),
                  child: TextField(
                    controller: _controller,
                    autofocus: !layout.isPhone,
                    onChanged: _onChanged,
                    onSubmitted: (v) {
                      _debounce?.cancel();
                      _onChanged(v);
                    },
                    textInputAction: TextInputAction.search,
                    style: VxText.body(16 * s),
                    decoration: InputDecoration(
                      hintText: 'Films, séries, acteurs…',
                      prefixIcon: const Icon(Icons.search_rounded, color: VxColors.textSecondary),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: const BorderSide(color: VxColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: const BorderSide(color: VxColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: const BorderSide(color: VxColors.accent, width: 2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _query.isEmpty ? _Browse(onPick: _use) : _Results(query: _query),
          ),
        ],
      ),
    );
  }
}

class _Browse extends ConsumerWidget {
  const _Browse({required this.onPick});

  final void Function(String) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    final recent = ref.watch(recentSearchesProvider);
    final genres = ref.watch(genresProvider(MediaType.movie));

    return ListView(
      padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 32),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text('Recherches récentes', style: VxText.title(17))),
              TextButton(
                onPressed: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: const Text('Effacer'),
              ),
            ],
          ),
          for (final q in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded, color: VxColors.textMuted),
              title: Text(q, style: VxText.body(15)),
              onTap: () => onPick(q),
              trailing: IconButton(
                tooltip: 'Retirer « $q » de l’historique',
                icon: const Icon(Icons.close_rounded, size: 18, color: VxColors.textMuted),
                onPressed: () => ref.read(recentSearchesProvider.notifier).remove(q),
              ),
            ),
          const SizedBox(height: 20),
        ],
        Text('Parcourir par genre', style: VxText.title(17)),
        const SizedBox(height: 12),
        AsyncView(
          value: genres,
          onRetry: () => ref.invalidate(genresProvider(MediaType.movie)),
          data: (list) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: layout.isLarge ? layout.tv(360) : 200,
              mainAxisExtent: layout.isLarge ? layout.tv(110) : 72,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: list.length,
            itemBuilder: (context, i) => VxFocusable(
              borderRadius: 14,
              semanticLabel: list[i].name,
              onPressed: () =>
                  context.push('/recherche/genre/movie/${list[i].id}?nom=${Uri.encodeQueryComponent(list[i].name)}'),
              child: Container(
                decoration: BoxDecoration(color: VxColors.tone(list[i].id), borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.all(14),
                alignment: Alignment.bottomLeft,
                child: Text(list[i].name, style: VxText.title(layout.isLarge ? layout.tv(24) : 15)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchProvider(query));
    final layout = Layout.of(context);
    return AsyncView(
      value: results,
      onRetry: () => ref.invalidate(searchProvider(query)),
      data: (r) => r.isEmpty
          ? EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Aucun résultat',
              message: 'Rien ne correspond à « $query ».',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (r.movies.isNotEmpty) PosterRow(title: 'Films', items: r.movies),
                if (r.shows.isNotEmpty) ...[const SizedBox(height: 24), PosterRow(title: 'Séries', items: r.shows)],
                if (r.people.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const SectionHeader('Personnes'),
                  SizedBox(
                    height: 132,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                      itemCount: r.people.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 16),
                      itemBuilder: (_, i) {
                        final p = r.people[i];
                        return SizedBox(
                          width: 84,
                          child: Column(
                            children: [
                              ClipOval(
                                child: SizedBox.square(
                                  dimension: 72,
                                  child: NetImage(
                                    url: p.profileUrl,
                                    seed: p.id,
                                    fallback: Center(child: Text(p.initials, style: VxText.title(22))),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                p.name,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                style: VxText.body(13, weight: FontWeight.w600, height: 1.2),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Titles of one genre (from "Parcourir par genre").
class GenreScreen extends ConsumerWidget {
  const GenreScreen({super.key, required this.type, required this.genreId, required this.name});

  final MediaType type;
  final int genreId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(discoverProvider((type, genreId)));
    return Scaffold(
      appBar: AppBar(
        title: Text(name, style: VxText.title(20)),
        backgroundColor: VxColors.background,
      ),
      body: AsyncView(
        value: items,
        onRetry: () => ref.invalidate(discoverProvider((type, genreId))),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.movie_filter_outlined, title: 'Aucun titre')
            : PosterGrid(items: list),
      ),
    );
  }
}
