import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';
import '../tv/channel_row.dart';
import '../tv/channel_search.dart';
import '../tv/models.dart';
import '../tv/tv_repository.dart';

/// The live-TV page, laid out like the home page: one row of channels per category, each with
/// a round arrow that shows the whole category. A text or a category chip shows a grid instead.
class TvChannelsScreen extends ConsumerStatefulWidget {
  const TvChannelsScreen({super.key});

  @override
  ConsumerState<TvChannelsScreen> createState() => _TvChannelsScreenState();
}

class _TvChannelsScreenState extends ConsumerState<TvChannelsScreen> {
  String _query = '';
  String? _categoryId;

  /// Rows by category (as on the home page), unless a text or a category narrows the channels.
  bool get _rows => _query.isEmpty && _categoryId == null;

  Future<void> _refresh() async {
    if (_rows) {
      ref.invalidate(tvCategoriesProvider);
      ref.invalidate(tvChannelRowsProvider);
      await ref.read(tvChannelRowsProvider.future);
      return;
    }
    ref.invalidate(tvCategoriesProvider);
    ref.invalidate(channelSearchProvider((_query, _categoryId)));
    await Future.wait([
      ref.read(tvCategoriesProvider.future),
      ref.read(channelSearchProvider((_query, _categoryId)).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final categories = ref.watch(tvCategoriesProvider).value ?? const <TvCategory>[];

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VxPageHeader(
            title: 'Chaînes TV',
            search: TextField(
              onChanged: (value) => setState(() => _query = value.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Rechercher une chaîne',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                isDense: true,
              ),
            ),
            filters: categories.isEmpty
                ? null
                : SizedBox(
                    height: layout.isLarge ? 56 : 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('Toutes'),
                            selected: _categoryId == null,
                            onSelected: (_) => setState(() => _categoryId = null),
                          ),
                        ),
                        for (final category in categories)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(category.name),
                              selected: _categoryId == category.id,
                              onSelected: (_) => setState(
                                () => _categoryId = _categoryId == category.id ? null : category.id,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (_rows) ..._rowSlivers(context) else ChannelSearchResults(query: _query, categoryId: _categoryId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _rowSlivers(BuildContext context) {
    final layout = Layout.of(context);
    return switch (ref.watch(tvChannelRowsProvider)) {
      AsyncData(:final value) when value.isEmpty => const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.live_tv_outlined,
            title: 'Aucune chaîne',
            message: 'Aucune chaîne disponible pour le moment.',
          ),
        ),
      ],
      AsyncData(:final value) => [
        // Room for the focus zoom on TV.
        SliverToBoxAdapter(child: SizedBox(height: layout.size(0, tv: 16))),
        SliverList.separated(
          itemCount: value.length,
          separatorBuilder: (_, _) => SizedBox(height: layout.sectionGap),
          itemBuilder: (_, i) {
            final section = value[i];
            final categoryId = section.categoryId;
            return ChannelRow(
              title: section.title,
              channels: section.channels,
              autofocusFirst: i == 0 && layout.isLarge,
              onSeeAll: categoryId == null ? null : () => setState(() => _categoryId = categoryId),
            );
          },
        ),
        // The last row ends above the tab bar.
        SliverToBoxAdapter(child: SizedBox(height: pageBottomPadding(context))),
      ],
      AsyncError(:final error) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorPanel(error: error, onRetry: () => ref.invalidate(tvChannelRowsProvider)),
        ),
      ],
      _ => const [SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
    };
  }
}
