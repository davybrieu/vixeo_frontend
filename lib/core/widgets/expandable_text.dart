import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../device/layout.dart';
import '../theme.dart';

/// Reusable expandable description with a discreet underline only while focused.
class ExpandableText extends StatefulWidget {
  const ExpandableText({super.key, required this.text, this.maxLines = 5, this.maxWidth});

  final String text;
  final int maxLines;
  final double? maxWidth;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final scale = layout.isLarge ? layout.scale * 2 : 1.0;
    final long = widget.text.length > 300;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth ?? double.infinity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _expanded || !long ? null : widget.maxLines,
            overflow: _expanded || !long ? null : TextOverflow.ellipsis,
            style: VxText.body(layout.isLarge ? layout.tv(25) : 15 * scale, color: VxColors.textSoft, height: 1.55),
          ),
          if (long)
            Focus(
              onFocusChange: (value) => setState(() => _focused = value),
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.space)) {
                  setState(() => _expanded = !_expanded);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: EdgeInsets.only(top: 6 * scale, bottom: 2),
                  child: Text(
                    _expanded ? 'Réduire' : 'Lire la suite',
                    style: VxText.body(14 * scale, color: VxColors.accent).copyWith(
                      decoration: _focused ? TextDecoration.underline : TextDecoration.none,
                      decorationColor: VxColors.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
