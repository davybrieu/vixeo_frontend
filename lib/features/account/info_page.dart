import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/focusable.dart';

/// Phone sizes × this factor on large screens (about the 1920 design's sizes).
double uiScale(BuildContext context) {
  final layout = Layout.of(context);
  return layout.isLarge ? layout.scale * 1.6 : 1.0;
}

/// Page of the account and legal screens: title bar, readable width, TV sizes.
/// Opened directly (web link, no history), the back button goes to [fallback].
class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.title, required this.children, this.fallback = '/connexion'});

  final String title;
  final List<Widget> children;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    final canPop = GoRouter.maybeOf(context)?.canPop() ?? Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: VxColors.background,
        title: Text(title, style: VxText.title(20 * s)),
        leading: canPop
            ? null
            : IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go(fallback),
              ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(layout.gutter, 8 * s, layout.gutter, 48 * s),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 720 * s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// Titled block of text. Focusable, so that on a TV the remote moves from block to block and
/// the page scrolls (plain text can't take the focus).
class InfoSection extends StatelessWidget {
  const InfoSection({super.key, required this.title, required this.children, this.autofocus = false});

  final String title;
  final List<Widget> children;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 12 * s),
      child: VxFocusable(
        autofocus: autofocus,
        borderRadius: 16 * s,
        focusScale: 1,
        child: Padding(
          padding: EdgeInsets.all(12 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: VxText.title(18 * s)),
              SizedBox(height: 8 * s),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Paragraph of an [InfoSection].
class InfoText extends StatelessWidget {
  const InfoText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8 * s),
      child: Text(text, style: VxText.body(15 * s, color: VxColors.textSoft)),
    );
  }
}

/// Bullet point of an [InfoSection].
class InfoBullet extends StatelessWidget {
  const InfoBullet(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final style = VxText.body(15 * s, color: VxColors.textSoft);
    return Padding(
      padding: EdgeInsets.only(bottom: 6 * s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style.copyWith(color: VxColors.accent)),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
