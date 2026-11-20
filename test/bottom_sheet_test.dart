import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/choice.dart';

void main() {
  testWidgets('phone: a list of choices opens above the tab bar, not under it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = GlobalKey<NavigatorState>();
    int? picked;

    // Like AppShell: the pages' navigator, and the tab bar drawn over it.
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: root,
        theme: buildVixeoTheme(),
        home: Scaffold(
          body: Stack(
            children: [
              Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () async {
                        final choice = await showVxChoice<int>(
                          context,
                          title: 'Trier par',
                          selected: 1,
                          options: const [(1, 'Popularité'), (2, 'Plus récents'), (3, 'Plus anciens')],
                        );
                        picked = choice?.$1;
                      },
                      child: const Text('Tri'),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 120,
                child: ColoredBox(color: Colors.black, child: Center(child: Text('Onglets'))),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tri'));
    await tester.pumpAndSettle();

    // On the app's own navigator, above everything the pages' one is under.
    expect(Navigator.of(tester.element(find.text('Trier par'))), root.currentState);
    // The last option, at the bottom of the sheet, is not hidden: a tap reaches it.
    await tester.tap(find.text('Plus anciens'));
    await tester.pumpAndSettle();
    expect(picked, 3);
  });
}
