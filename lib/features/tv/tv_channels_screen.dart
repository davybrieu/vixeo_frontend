import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/layout.dart';
import '../../core/widgets/page_header.dart';
import '../tv/channel_search.dart';
import '../tv/models.dart';
import '../tv/tv_repository.dart';

/// Dedicated live-TV catalogue, with the same channel tiles and playback flow as home/search.
class TvChannelsScreen extends ConsumerStatefulWidget {
  const TvChannelsScreen({super.key});

  @override
  ConsumerState<TvChannelsScreen> createState() => _TvChannelsScreenState();
}

class _TvChannelsScreenState extends ConsumerState<TvChannelsScreen> {
  String _query = '';
  String? _categoryId;

  Future<void> _refresh() async {
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
                  ChannelSearchResults(query: _query, categoryId: _categoryId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
