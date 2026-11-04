import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/app.dart';
import 'package:vixeo/core/device/layout.dart';
import 'package:vixeo/core/widgets/focusable.dart';

void main() {
  test('picks the layout from the width, and always the large one on a TV', () {
    expect(Layout.forWidth(390).formFactor, FormFactor.phone);
    expect(Layout.forWidth(800).formFactor, FormFactor.tablet);
    expect(Layout.forWidth(1440).formFactor, FormFactor.large);
    // A 1080p Android TV is usually 960 dp wide.
    final tv = Layout.forWidth(960, isTv: true);
    expect(tv.formFactor, FormFactor.large);
    expect(tv.tv(100), 50);
    expect(Layout.forWidth(1920).tv(72), 72);
  });

  testWidgets('a remote can focus and activate an element (arrows + OK)', (tester) async {
    var pressed = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              VxFocusable(
                autofocus: true,
                onPressed: () => pressed = 'first',
                child: const SizedBox(width: 100, height: 100),
              ),
              VxFocusable(onPressed: () => pressed = 'second', child: const SizedBox(width: 100, height: 100)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(pressed, 'second');
  });

  testWidgets('the menu key opens the context menu', (tester) async {
    var menu = false;
    await tester.pumpWidget(
      MaterialApp(
        home: VxFocusable(
          autofocus: true,
          onPressed: () {},
          onLongPress: () => menu = true,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(menu, isTrue);
  });

  testWidgets('the app keys work the same on the web: arrows move the focus, Enter activates', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var pressed = '';
    await tester.pumpWidget(
      MaterialApp(
        shortcuts: remoteShortcuts,
        home: Scaffold(
          body: ListView(
            children: [
              VxFocusable(autofocus: true, onPressed: () => pressed = 'top', child: const SizedBox(height: 100)),
              VxFocusable(onPressed: () => pressed = 'bottom', child: const SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(pressed, 'bottom');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an arrow key focuses the first element when nothing has the focus yet', (tester) async {
    var pressed = '';
    await tester.pumpWidget(
      MaterialApp(
        shortcuts: remoteShortcuts,
        actions: remoteActions,
        home: Scaffold(
          body: Column(
            children: [
              VxFocusable(onPressed: () => pressed = 'first', child: const SizedBox(height: 50, width: 50)),
              VxFocusable(onPressed: () => pressed = 'second', child: const SizedBox(height: 50, width: 50)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(hasFocusedElement(), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(pressed, 'first');
  });
}
