import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/page_header.dart';

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
      body: InfoBody(children: children),
    );
  }
}

/// Body of a secondary page (charte graphique, § 6): one column of reading width, centered, at the
/// page margins, 8 (TV 12) under the title bar and the end clear of what covers the page. Its
/// blocks line up on the column's edges (no extra inset) and are [VxSizes.sectionGap] apart.
class InfoBody extends StatelessWidget {
  const InfoBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final s = uiScale(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(layout.gutter, layout.space(VxSpace.xs), layout.gutter, pageBottomPadding(context)),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 720 * s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ],
    );
  }
}

/// The sentence that introduces a secondary page, over its content.
class InfoIntro extends StatelessWidget {
  const InfoIntro(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: Layout.of(context).introGap),
    child: Text(text, style: VxText.body(15 * uiScale(context), color: VxColors.textSecondary)),
  );
}

/// Titled block: its title, then what it holds, and a section gap under it (none for the [last]
/// one). Not focusable (VxFocusable only focuses what can be pressed): on a TV, the remote goes from
/// button to button and the page scrolls with them.
class InfoSection extends StatelessWidget {
  const InfoSection({super.key, required this.title, required this.children, this.last = false});

  final String title;
  final List<Widget> children;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : layout.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: VxText.title(18 * uiScale(context))),
          SizedBox(height: layout.titleGap),
          ...children,
        ],
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
      padding: EdgeInsets.only(bottom: Layout.of(context).space(VxSpace.xs)),
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
