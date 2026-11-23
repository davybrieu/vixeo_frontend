import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/focusable.dart';
import '../../core/widgets/page_header.dart';

/// The whole summary of a title, or a person's whole biography (`/description`, opened by « Lire
/// la suite », `DescriptionLink`): back, the title, then the text, at a reading width. The text has
/// the focus on arrival: Up / Down of the remote scroll it; Up at the top goes to « Retour ».
class DescriptionScreen extends StatefulWidget {
  const DescriptionScreen({super.key, required this.title, required this.text});

  static const location = '/description';

  final String title;
  final String text;

  /// Opens the page (the text travels with the route, never in its address).
  static Future<void> open(BuildContext context, {required String title, required String text}) =>
      context.push(location, extra: (title: title, text: text));

  /// The text given to the route by [open]; null when the page is opened without it.
  static DescriptionScreen? fromExtra(Object? extra) =>
      extra is ({String title, String text}) ? DescriptionScreen(title: extra.title, text: extra.text) : null;

  @override
  State<DescriptionScreen> createState() => _DescriptionScreenState();
}

class _DescriptionScreenState extends State<DescriptionScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if ((!down && !up) || !_scroll.hasClients) return KeyEventResult.ignored;
    final position = _scroll.position;
    // At the top, Up leaves the text for « Retour ».
    if (up && position.pixels <= position.minScrollExtent) return KeyEventResult.ignored;
    final step = position.viewportDimension * 0.4;
    final target = (position.pixels + (down ? step : -step)).clamp(position.minScrollExtent, position.maxScrollExtent);
    _scroll.animateTo(target.toDouble(), duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VxPageHeader(title: widget.title, back: true),
            Expanded(
              child: Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, pageBottomPadding(context)),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: layout.size(720, tv: 1400)),
                    child: Text(
                      widget.text,
                      style: VxText.body(layout.size(16, tv: 26), color: VxColors.textSoft, height: 1.7),
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

/// A title's summary or a person's biography on its page: its first [maxLines] lines and, only
/// when it is longer, « Lire la suite », which opens the whole text on a page of its own
/// ([DescriptionScreen]). Only the link is focusable (the text is not pressed).
class DescriptionLink extends StatelessWidget {
  const DescriptionLink({super.key, required this.title, required this.description, this.maxLines = 5, this.maxWidth});

  /// Written above the whole text (the title, the person's name).
  final String title;
  final String description;
  final int maxLines;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final style = VxText.body(layout.size(15, tv: 24), color: VxColors.textSoft, height: 1.55);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: description, style: style),
            maxLines: maxLines,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          final longer = painter.didExceedMaxLines;
          painter.dispose();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(description, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style),
              if (longer)
                VxFocusable(
                  borderRadius: layout.size(6, tv: 10),
                  semanticLabel: 'Lire la suite : $title',
                  onPressed: () => DescriptionScreen.open(context, title: title, text: description),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: layout.space(VxSpace.xxs)),
                    child: Text(
                      'Lire la suite',
                      style: VxText.body(layout.size(14, tv: 22), weight: FontWeight.w600, color: VxColors.accent),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
