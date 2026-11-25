import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../design.dart';
import '../device/layout.dart';
import '../theme.dart';
import 'focus_navigation.dart';
import 'focusable.dart';

/// One line of a menu: its icon, its label and what a press does; [danger]: red (« Se
/// déconnecter », « Bloquer »).
typedef VxMenuItem = ({IconData icon, String label, VoidCallback onTap, bool danger});

VxMenuItem vxMenuItem(IconData icon, String label, VoidCallback onTap, {bool danger = false}) =>
    (icon: icon, label: label, onTap: onTap, danger: danger);

/// A drop-down menu under the button that opens it ([anchor]: the button's context, from a
/// `Builder` around it), right-aligned with it (left-aligned when the button is on the left of
/// the screen), above it when there is no room below. The first line has the focus (remote); Retour
/// or a press outside closes it. [label]: what screen readers say of it.
///
/// Flutter: a menu is a route pushed over the page, like a dialog (`showDialog`), but transparent
/// and placed by hand next to its button (`CustomSingleChildLayout`).
Future<void> showVxMenu(BuildContext anchor, {required List<VxMenuItem> items, String label = 'Menu'}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final navigator = Navigator.of(anchor, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject() as RenderBox?;
  final rect = box == null || overlay == null
      ? Rect.zero
      : Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlay),
          box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
        );
  return navigator.push(_MenuRoute(anchor: rect, items: items, label: label));
}

class _MenuRoute extends PopupRoute<void> {
  _MenuRoute({required this.anchor, required this.items, required this.label});

  final Rect anchor;
  final List<VxMenuItem> items;
  final String label;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.25);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Fermer le menu';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final padding = MediaQuery.paddingOf(context) + const EdgeInsets.all(8);
    final left = anchor.center.dx < MediaQuery.sizeOf(context).width / 2;
    return CustomSingleChildLayout(
      delegate: _MenuLayout(anchor: anchor, padding: padding, gap: Layout.of(context).space(VxSpace.xs)),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          alignment: left ? Alignment.topLeft : Alignment.topRight,
          scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: _Menu(items: items, label: label),
        ),
      ),
    );
  }
}

/// Places the menu under [anchor] (above it without room below), inside [padding].
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor, required this.padding, required this.gap});

  final Rect anchor;
  final EdgeInsets padding;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(padding);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final onLeft = anchor.center.dx < size.width / 2;
    final maxX = math.max(padding.left, size.width - padding.right - child.width);
    final x = (onLeft ? anchor.left : anchor.right - child.width).clamp(padding.left, maxX);
    var y = anchor.bottom + gap;
    if (y + child.height > size.height - padding.bottom) y = anchor.top - gap - child.height;
    final maxY = math.max(padding.top, size.height - padding.bottom - child.height);
    return Offset(x, y.clamp(padding.top, maxY));
  }

  @override
  bool shouldRelayout(_MenuLayout old) => anchor != old.anchor || padding != old.padding || gap != old.gap;
}

class _Menu extends StatelessWidget {
  const _Menu({required this.items, required this.label});

  final List<VxMenuItem> items;
  final String label;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final radius = layout.size(VxRadius.card, tv: VxRadius.cardTv) * 0.8;
    final iconSize = layout.size(22, tv: 34);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: label,
      child: Material(
        color: VxColors.surfaceHigh,
        elevation: 12,
        shadowColor: Colors.black,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: layout.size(240, tv: 420), maxWidth: layout.size(320, tv: 560)),
          child: IntrinsicWidth(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.xs)),
              child: FocusTraversalGroup(
                policy: vxTraversalPolicy,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, item) in items.indexed)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: layout.space(VxSpace.xs)),
                        child: VxFocusable(
                          autofocus: i == 0,
                          focusScale: 1.02,
                          borderRadius: layout.size(VxRadius.button, tv: VxRadius.buttonTv),
                          semanticLabel: item.label,
                          onPressed: () {
                            Navigator.of(context).pop();
                            item.onTap();
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: layout.space(VxSpace.s),
                              vertical: layout.space(VxSpace.s),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.icon,
                                  size: iconSize,
                                  color: item.danger ? VxColors.dangerText : VxColors.textSoft,
                                ),
                                SizedBox(width: layout.space(VxSpace.s)),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: VxText.body(
                                      layout.bodySize,
                                      weight: FontWeight.w600,
                                      color: item.danger ? VxColors.dangerText : VxColors.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
