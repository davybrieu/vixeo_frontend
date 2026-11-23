import 'package:material_ui/material_ui.dart';

import '../design.dart';
import '../device/layout.dart';
import '../theme.dart';
import 'focus_navigation.dart';
import 'focusable.dart';

/// Tabs in a segmented bar: « Pour toi » / « Abonnements » of « Fil », « Activité » / « Listes » /
/// « Journal » of a profile page. A press (or OK with the remote) changes the tab; each tab is read
/// « Pour toi, onglet 1 sur 2 », selected or not.
///
/// Flutter: a widget without state of its own (like a Vue component with a `v-model`): the page
/// keeps [selected] and changes it in [onSelected].
class VxTabs extends StatelessWidget {
  const VxTabs({super.key, required this.labels, required this.selected, required this.onSelected});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final radius = layout.size(VxRadius.button, tv: VxRadius.buttonTv);
    return FocusTraversalGroup(
      policy: vxTraversalPolicy,
      child: Container(
        padding: EdgeInsets.all(layout.space(VxSpace.xxs)),
        decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(radius + 4)),
        child: Row(
          children: [
            for (final (i, label) in labels.indexed)
              Expanded(
                child: Semantics(
                  selected: i == selected,
                  child: VxFocusable(
                    borderRadius: radius,
                    focusScale: 1.02,
                    semanticLabel: '$label, onglet ${i + 1} sur ${labels.length}',
                    onPressed: () => onSelected(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.xs)),
                      decoration: BoxDecoration(
                        color: i == selected ? VxColors.surfaceHigh : Colors.transparent,
                        borderRadius: BorderRadius.circular(radius),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VxText.body(
                          layout.captionSize,
                          weight: FontWeight.w700,
                          color: i == selected ? VxColors.text : VxColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
