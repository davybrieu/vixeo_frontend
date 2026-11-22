import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/focusable.dart';

class DescriptionScreen extends StatefulWidget {
  const DescriptionScreen({super.key, required this.title, required this.description});

  final String title;
  final String description;

  @override
  State<DescriptionScreen> createState() => _DescriptionScreenState();
}

class _DescriptionScreenState extends State<DescriptionScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final distance = Layout.of(context).isLarge ? 100.0 : 48.0;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final delta = event.logicalKey == LogicalKeyboardKey.arrowDown ? distance : -distance;
      _scrollController.animateTo(
        (_scrollController.offset + delta).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final scale = layout.isLarge ? layout.tv(1) : 1.0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.m), layout.gutter, layout.space(VxSpace.l)),
              child: VxFocusable(
                autofocus: true,
                borderRadius: 24 * scale,
                semanticLabel: 'Retour',
                onPressed: () => context.canPop() ? context.pop() : context.go('/accueil'),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 10 * scale),
                  decoration: BoxDecoration(
                    color: VxColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(24 * scale),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded, size: 22 * scale, color: VxColors.text),
                      SizedBox(width: 8 * scale),
                      Text('Retour', style: VxText.body(16 * scale, color: VxColors.text)),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.gutter),
              child: Text(
                widget.title,
                style: VxText.title(layout.isLarge ? layout.tv(42) : 26, weight: FontWeight.w800),
              ),
            ),
            SizedBox(height: layout.space(VxSpace.m)),
            Expanded(
              child: Focus(
                onKeyEvent: _handleKey,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, layout.sectionGap),
                  child: Text(
                    widget.description,
                    style: VxText.body(layout.isLarge ? layout.tv(24) : 16, color: VxColors.textSoft, height: 1.7),
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
