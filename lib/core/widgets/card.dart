import 'package:flutter/material.dart';

import '../design.dart';
import '../device/layout.dart';
import '../theme.dart';

/// Panel of the charter (docs/charte-graphique.md, « Cartes ») : surface color, a thin border,
/// radius 20 (28 on TV), padding 20 (30 on TV). A Material, so that switches and ink inside draw
/// on it.
class VxCard extends StatelessWidget {
  const VxCard({super.key, required this.child, this.padding});

  final Widget child;

  /// Default: 20 on phones, 30 on TV.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Material(
      color: VxColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(layout.size(VxRadius.card, tv: VxRadius.cardTv)),
        side: const BorderSide(color: VxColors.surfaceHigh),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.all(layout.size(20, tv: 30)),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
