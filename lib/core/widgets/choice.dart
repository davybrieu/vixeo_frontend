import 'package:flutter/material.dart';

import '../device/layout.dart';
import '../theme.dart';
import 'focusable.dart';

/// List of choices (search filters, playback settings): bottom sheet on a phone, dialog on larger screens. The current
/// choice has the focus (TV). Returns the chosen value in a record (`(null,)` = "Tous"), or null
/// when closed without choosing.
Future<(T?,)?> showVxChoice<T>(
  BuildContext context, {
  required String title,
  required List<(T?, String)> options,
  required T? selected,
}) {
  final layout = Layout.of(context);
  final large = !layout.isPhone;

  Widget list(BuildContext context) {
    final s = layout.isLarge ? layout.tv(1) * 1.6 : 1.0;
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(12 * s, 0, 12 * s, 16 * s),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12 * s, large ? 20 * s : 0, 12 * s, 12 * s),
          child: Text(title, style: VxText.title(20 * s)),
        ),
        for (final (value, label) in options)
          VxFocusable(
            autofocus: value == selected,
            borderRadius: 12 * s,
            semanticLabel: value == selected ? '$label, sélectionné' : label,
            onPressed: () => Navigator.of(context).pop((value,)),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 13 * s),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: VxText.body(
                        16 * s,
                        weight: value == selected ? FontWeight.w600 : FontWeight.w400,
                        color: value == selected ? VxColors.accent : VxColors.text,
                      ),
                    ),
                  ),
                  if (value == selected) Icon(Icons.check_rounded, size: 22 * s, color: VxColors.accent),
                ],
              ),
            ),
          ),
      ],
    );
  }

  if (!large) {
    return showModalBottomSheet<(T?,)>(
      context: context,
      backgroundColor: VxColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7),
        child: list(sheetContext),
      ),
    );
  }
  return showDialog<(T?,)>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: VxColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: layout.isLarge ? layout.tv(620) : 420,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.8,
        ),
        child: list(dialogContext),
      ),
    ),
  );
}
