import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';
import '../profiles/row_preferences.dart';
import '../tv/channel_row.dart';
import '../tv/channel_search.dart';

/// The live-TV page, laid out like the home page: its title, then one row of channels per
/// category (every category that has channels). The round arrow of a row opens the whole
/// category ([TvCategoryScreen]). No search field nor category filter here (developer's
/// request): channels are searched in the search page.
class TvChannelsScreen extends ConsumerWidget {
  const TvChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);

    Future<void> refresh() async {
      ref.invalidate(tvChannelRowsProvider);
      await ref.read(tvChannelRowsProvider.future);
    }

    // The categories the profile chose to show, in its order (« Paramètres »).
    final rowPreferences = ref.watch(channelRowPreferencesProvider).value ?? RowPreferences.none;
    final allRows = ref.watch(tvChannelRowsProvider);
    final rows = allRows.whenData((all) => rowPreferences.visible(all, channelRowKey));
    final everyRowHidden = (allRows.value?.isNotEmpty ?? false) && (rows.value?.isEmpty ?? false);

    final List<Widget> content = switch (rows) {
      AsyncData() when everyRowHidden => const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.visibility_off_outlined,
            title: 'Toutes les catégories sont masquées',
            message: 'Affichez-en dans Paramètres, « Catégories des chaînes TV ».',
          ),
        ),
      ],
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
          itemBuilder: (context, i) {
            final section = value[i];
            final categoryId = section.categoryId;
            return ChannelRow(
              title: section.title,
              channels: section.channels,
              autofocusFirst: i == 0 && layout.isLarge,
              onSeeAll: categoryId == null
                  ? null
                  : () => context.push(TvCategoryScreen.location(categoryId, section.title)),
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

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VxPageHeader(title: 'Chaînes TV'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: content),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every channel of one category (the round arrow of a row of the « Chaînes TV » page): back
/// button, the category's name, then the grid of its channels.
class TvCategoryScreen extends StatelessWidget {
  const TvCategoryScreen({super.key, required this.categoryId, this.title});

  final String categoryId;

  /// The category's name; without it (address typed by hand), « Chaînes TV ».
  final String? title;

  static String location(String categoryId, String title) =>
      '/chaines-tv/categorie/${Uri.encodeComponent(categoryId)}?titre=${Uri.encodeQueryComponent(title)}';

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = layout.isLarge ? layout.scale * 2 : 1.0;
    final heading = (title == null || title!.trim().isEmpty) ? 'Chaînes TV' : title!;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.xs), layout.gutter, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VxFocusable(
                    borderRadius: 22 * s,
                    semanticLabel: 'Retour',
                    autofocus: layout.isLarge,
                    onPressed: () => context.canPop() ? context.pop() : context.go('/chaines-tv'),
                    child: Container(
                      width: 44 * s,
                      height: 44 * s,
                      decoration: const BoxDecoration(color: VxColors.surfaceHigh, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_rounded, color: VxColors.text, size: 22 * s),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.gutter,
                  layout.space(VxSpace.m),
                  layout.gutter,
                  layout.space(VxSpace.xs),
                ),
                child: Text(heading, style: VxText.title(layout.pageTitleSize)),
              ),
            ),
            ChannelSearchResults(query: '', categoryId: categoryId),
            // The end of the page clear of what covers it.
            SliverToBoxAdapter(child: SizedBox(height: pageBottomPadding(context))),
          ],
        ),
      ),
    );
  }
}
