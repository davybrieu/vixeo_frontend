import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/focusable.dart';
import '../account/info_page.dart';

/// A titled group of settings, with the same gaps everywhere (charte graphique, § 5): 12 (TV 22)
/// under the title, 8 (TV 12) between two rows, 24 (TV 36) before the next group. Lined up on the
/// page's column, like the other secondary pages. Used by « Paramètres », « Notifications » and
/// « Avancé ».
class SettingsSection extends StatelessWidget {
  const SettingsSection(this.title, {super.key, required this.scale, required this.children, this.last = false});

  final String title;
  final double scale;
  final List<Widget> children;

  /// The last group: nothing under it.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : layout.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: VxText.title(18 * scale)),
          SizedBox(height: layout.titleGap),
          for (final (i, row) in children.indexed) ...[if (i > 0) SizedBox(height: layout.space(VxSpace.xs)), row],
        ],
      ),
    );
  }
}

/// A setting whose value is picked in a list.
class SettingsChoiceRow extends StatelessWidget {
  const SettingsChoiceRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: 14 * s,
      focusScale: 1.02,
      semanticLabel: '$label : $value',
      onPressed: onPressed,
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 14 * s),
          decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(14 * s)),
          child: Row(
            children: [
              Icon(icon, size: 22 * s, color: VxColors.textSoft),
              SizedBox(width: 14 * s),
              Expanded(
                child: Text(label, style: VxText.body(15 * s, weight: FontWeight.w600)),
              ),
              Text(
                value,
                style: VxText.body(15 * s, color: VxColors.accent, weight: FontWeight.w600),
              ),
              SizedBox(width: 6 * s),
              Icon(Icons.chevron_right_rounded, size: 22 * s, color: VxColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// An on / off setting: the whole row is the switch (remote: OK toggles it). Screen readers say
/// the label then [onLabel] or [offLabel].
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
    this.onLabel = 'activé',
    this.offLabel = 'désactivé',
    this.autofocus = false,
  });

  final String label;
  final String detail;
  final bool value;

  /// Null: shown greyed, can't be changed.
  final ValueChanged<bool>? onChanged;
  final String onLabel;
  final String offLabel;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      child: VxFocusable(
        autofocus: autofocus,
        borderRadius: 14 * s,
        focusScale: 1.02,
        semanticLabel: '$label, ${value ? onLabel : offLabel}',
        onPressed: enabled ? () => onChanged!(!value) : null,
        child: ExcludeSemantics(
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
              decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(14 * s)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: VxText.body(15 * s, weight: FontWeight.w600)),
                        SizedBox(height: 2 * s),
                        Text(detail, style: VxText.body(13 * s, color: VxColors.textSecondary)),
                      ],
                    ),
                  ),
                  SizedBox(width: 12 * s),
                  // The row handles taps and the remote: the switch only shows the state.
                  IgnorePointer(
                    child: ExcludeFocus(
                      child: Transform.scale(
                        scale: s,
                        child: Switch(value: value, onChanged: (_) {}, activeThumbColor: VxColors.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A setting that does something at once (empty the cache, send a test notification…): label,
/// one sentence, then a spinner while it runs.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.detail,
    required this.onPressed,
    this.busy = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String detail;

  /// Null: shown greyed.
  final VoidCallback? onPressed;
  final bool busy;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final enabled = onPressed != null;
    return VxFocusable(
      autofocus: autofocus,
      borderRadius: 14 * s,
      focusScale: 1.02,
      semanticLabel: '$label. $detail',
      onPressed: enabled && !busy ? onPressed : null,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
            decoration: BoxDecoration(color: VxColors.surface, borderRadius: BorderRadius.circular(14 * s)),
            child: Row(
              children: [
                Icon(icon, size: 22 * s, color: VxColors.textSoft),
                SizedBox(width: 14 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: VxText.body(15 * s, weight: FontWeight.w600)),
                      SizedBox(height: 2 * s),
                      Text(detail, style: VxText.body(13 * s, color: VxColors.textSecondary)),
                    ],
                  ),
                ),
                SizedBox(width: 12 * s),
                SizedBox.square(
                  dimension: 22 * s,
                  child: busy
                      ? const CircularProgressIndicator(strokeWidth: 2.4)
                      : Icon(Icons.chevron_right_rounded, size: 22 * s, color: VxColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
