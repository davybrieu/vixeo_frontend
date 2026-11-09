import 'package:flutter/material.dart';

import '../design.dart';
import '../device/layout.dart';
import '../theme.dart';

/// Top of a main page (Recherche, Ma liste, Avis): its title, a search field and a filter bar,
/// with the same spacing everywhere (docs/charte-graphique.md, « En-tête de page »):
/// 16 above the title, 16 between the title and the field, 12 before the filters, 16 before the
/// content (×1.5 on TV). The filter bar scrolls sideways and brings its own side margins.
class VxPageHeader extends StatelessWidget {
  const VxPageHeader({super.key, required this.title, this.search, this.filters});

  final String title;
  final Widget? search;
  final Widget? filters;

  /// Widest search field on tablets and large screens.
  static double searchMaxWidth(Layout layout) => layout.isPhone ? double.infinity : layout.size(720, tv: 1100);

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.m), layout.gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: VxText.title(layout.pageTitleSize)),
              if (search != null) ...[
                SizedBox(height: layout.space(VxSpace.m)),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: searchMaxWidth(layout)),
                  child: search,
                ),
              ],
            ],
          ),
        ),
        if (filters != null) ...[SizedBox(height: layout.space(VxSpace.s)), filters!],
        SizedBox(height: layout.space(VxSpace.m)),
      ],
    );
  }
}

/// Padding of the content under a [VxPageHeader] (grid, list): the page's side margins; on top,
/// only the room for the focus zoom on TV (the header already spaces it); at the bottom, 32 plus
/// what the tab bar covers.
EdgeInsets pageContentPadding(BuildContext context) {
  final layout = Layout.of(context);
  return EdgeInsets.fromLTRB(layout.gutter, layout.size(0, tv: 16), layout.gutter, pageBottomPadding(context));
}

/// Under the last element of a scrolling page: 32 (TV 48), plus what the phone's tab bar covers
/// (in the media padding), so nothing ends under it.
double pageBottomPadding(BuildContext context) =>
    Layout.of(context).space(VxSpace.xl) + MediaQuery.paddingOf(context).bottom;
