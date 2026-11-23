import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/catalog/description_screen.dart';

// A summary or a biography: its first lines on the page, « Lire la suite » (only when it is longer)
// opens the whole text on a page of its own.

Future<void> _pump(WidgetTester tester, String text) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: DescriptionLink(title: 'Les Veilleurs', description: text),
          ),
        ),
      ),
      GoRoute(
        path: DescriptionScreen.location,
        redirect: (_, state) => DescriptionScreen.fromExtra(state.extra) == null ? '/' : null,
        builder: (_, state) => DescriptionScreen.fromExtra(state.extra)!,
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(theme: buildVixeoTheme(), routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a short text is written whole, without « Lire la suite »', (tester) async {
    await _pump(tester, 'Résumé court.');

    expect(find.text('Résumé court.'), findsOneWidget);
    expect(find.text('Lire la suite'), findsNothing);
  });

  testWidgets('a long text: its first lines, then « Lire la suite » opens it whole', (tester) async {
    final text = List.filled(40, 'Une phrase du résumé qui continue.').join(' ');
    await _pump(tester, text);

    expect(find.text('Lire la suite'), findsOneWidget);
    await tester.tap(find.text('Lire la suite'));
    await tester.pumpAndSettle();

    expect(find.byType(DescriptionScreen), findsOneWidget);
    expect(find.text('Les Veilleurs'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is VxFocusable && widget.semanticLabel == 'Retour'), findsOneWidget);
  });
}
