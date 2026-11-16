import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';

/// Opacity of a page as it is painted (every fade around it); 0 once the page is closed.
double _opacityOf(WidgetTester tester, String text) {
  final page = find.text(text, skipOffstage: false);
  if (page.evaluate().isEmpty) return 0;
  var opacity = 1.0;
  final fades = find.ancestor(of: page, matching: find.byType(FadeTransition));
  for (final fade in tester.widgetList<FadeTransition>(fades)) {
    opacity *= fade.opacity.value;
  }
  return opacity;
}

/// Size of a page as it is painted (1 = full size).
double _scaleOf(WidgetTester tester, String text) {
  var scale = 1.0;
  final scales = find.ancestor(of: find.text(text, skipOffstage: false), matching: find.byType(ScaleTransition));
  for (final transition in tester.widgetList<ScaleTransition>(scales)) {
    scale *= transition.scale.value;
  }
  return scale;
}

void main() {
  testWidgets('page change: the old page fades out before the new one fades in, the same way back', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildVixeoTheme(),
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Accueil')),
      ),
    );

    const step = Duration(milliseconds: 20);
    final steps = vxPageFade.inMilliseconds ~/ step.inMilliseconds;

    // Forward: « Fiche » arrives over « Accueil ».
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Fiche'))));
    await tester.pump();
    final leavingForward = <double>[];
    final arrivingForward = <double>[];
    for (var i = 0; i <= steps; i++) {
      final old = _opacityOf(tester, 'Accueil');
      final arriving = _opacityOf(tester, 'Fiche');
      // Never the two pages on top of each other.
      expect(old * arriving, lessThan(0.05), reason: 'at ${i * step.inMilliseconds} ms');
      leavingForward.add(old);
      arrivingForward.add(arriving);
      if (i == steps ~/ 2) {
        // Halfway: the new page is appearing, still a little smaller (it grows, it doesn't slide).
        expect(arriving, greaterThan(0));
        expect(_scaleOf(tester, 'Fiche'), inExclusiveRange(VxPageTransition.startScale, 1));
        expect(_scaleOf(tester, 'Accueil'), 1, reason: 'the page that leaves only fades out');
      }
      await tester.pump(step);
    }
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'Fiche'), 1);
    expect(_scaleOf(tester, 'Fiche'), 1);
    expect(leavingForward.first, 1);
    expect(arrivingForward.first, 0);

    // Back: « Fiche » closes, « Accueil » comes back, with the same timing.
    navigator.currentState!.pop();
    await tester.pump();
    for (var i = 0; i <= steps; i++) {
      final leaving = _opacityOf(tester, 'Fiche');
      final arriving = _opacityOf(tester, 'Accueil');
      expect(leaving * arriving, lessThan(0.05), reason: 'at ${i * step.inMilliseconds} ms');
      expect(leaving, closeTo(leavingForward[i], 0.03), reason: 'leaves like forward, at ${i * step.inMilliseconds} ms');
      expect(arriving, closeTo(arrivingForward[i], 0.03), reason: 'arrives like forward, at ${i * step.inMilliseconds} ms');
      await tester.pump(step);
    }
    await tester.pumpAndSettle();
    expect(find.text('Fiche'), findsNothing);
    expect(_opacityOf(tester, 'Accueil'), 1);
    expect(_scaleOf(tester, 'Accueil'), 1);
  });
}
