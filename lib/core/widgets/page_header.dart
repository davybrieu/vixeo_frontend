import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../design.dart';
import '../device/layout.dart';
import '../theme.dart';
import 'focusable.dart';

/// Top of a main page (Recherche, À voir, Avis): its title, a search field and a filter bar,
/// with the same spacing everywhere (docs/charte-graphique.md, « En-tête de page »):
/// 16 above the title, 16 between the title and the field, 12 before the filters, 16 before the
/// content (×1.5 on TV). The filter bar scrolls sideways and brings its own side margins.
class VxPageHeader extends StatelessWidget {
  const VxPageHeader({
    super.key,
    required this.title,
    this.search,
    this.filters,
    this.back = false,
    this.actions = const [],
  });

  final String title;

  /// Round buttons on the right of the title (« Messages » of the feed…).
  final List<Widget> actions;
  final Widget? search;
  final Widget? filters;

  /// A round back button above the title: a page opened over another one (« À voir » from the
  /// profile page). The tabs have none, so that their titles are at the same place.
  final bool back;

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
              if (back) ...[const VxBackButton(), SizedBox(height: layout.space(VxSpace.m))],
              if (actions.isEmpty)
                Text(title, style: VxText.title(layout.pageTitleSize))
              else
                Row(
                  children: [
                    Expanded(child: Text(title, style: VxText.title(layout.pageTitleSize))),
                    for (final (i, action) in actions.indexed) ...[
                      if (i > 0) SizedBox(width: layout.space(VxSpace.xs)),
                      action,
                    ],
                  ],
                ),
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

/// Round back button at the top of a page opened over another one: back, or to the home page.
class VxBackButton extends StatelessWidget {
  const VxBackButton({super.key, this.onPressed});

  /// What the button does instead of the usual back (the player has its own).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.size(44, tv: 76);
    return VxFocusable(
      borderRadius: size / 2,
      semanticLabel: 'Retour',
      onPressed: onPressed ?? () {
        final router = GoRouter.maybeOf(context);
        if (router == null) {
          Navigator.of(context).maybePop();
        } else if (router.canPop()) {
          router.pop();
        } else {
          router.go('/accueil');
        }
      },
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: VxColors.surfaceHigh, shape: BoxShape.circle),
        child: Icon(Icons.arrow_back_rounded, color: VxColors.text, size: size / 2),
      ),
    );
  }
}
