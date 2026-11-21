import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/range_slider.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/search/search_filters.dart';

void main() {
  group('RangeStops', () {
    test('the ends of the track mean no limit; a value goes to the nearest position', () {
      const stops = RangeStops.votes;
      expect(stops.indexesOf(null, null), (0, stops.count - 1));
      expect(stops.valuesAt((0, stops.count - 1)), (null, null));
      expect(stops.indexesOf(1000, 50000), (3, 8));
      expect(stops.valuesAt((3, 8)), (1000, 50000));
      expect(stops.indexesOf(1100, null), (3, stops.count - 1));

      final years = RangeStops.years();
      expect((years.values.first, years.values.last), (1900, DateTime.now().year));
      expect(years.valuesAt(years.indexesOf(2010, 2019)), (2010, 2019));
      expect(RangeStops.ratings.valuesAt(RangeStops.ratings.indexesOf(6.5, 8)), (6.5, 8));
    });

    test('labels of the chips', () {
      expect(yearRangeLabel(null, null), isNull);
      expect(yearRangeLabel(2010, null), 'Depuis 2010');
      expect(yearRangeLabel(null, 1979), 'Jusqu’à 1979');
      expect(yearRangeLabel(2015, 2015), '2015');
      expect(yearRangeLabel(2010, 2019), '2010–2019');
      expect(ratingRangeLabel(7, null), 'Note ≥ 7');
      expect(ratingRangeLabel(null, 6.5), 'Note ≤ 6,5');
      expect(ratingRangeLabel(6, 8.5), 'Note 6–8,5');
      expect(votesRangeLabel(10000, null), 'Votants ≥ ${formatCount(10000)}');
      expect(votesRangeLabel(1000, 50000), 'Votants ${formatCount(1000)}–${formatCount(50000)}');
    });
  });

  group('VxRangeSlider', () {
    late (int, int) values;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      values = (2, 8);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildVixeoTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (context, setState) => VxRangeSlider(
                    count: 11,
                    values: values,
                    onChanged: (v) => setState(() => values = v),
                    label: 'Années',
                    valueLabel: (i) => '$i',
                    autofocus: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Where position [index] is drawn (thumbs of 11 px, the track 1,4 thumb from each side).
    Offset at(WidgetTester tester, int index) {
      final rect = tester.getRect(find.byType(VxRangeSlider));
      const inset = 11 * 1.4;
      return Offset(rect.left + inset + (rect.width - 2 * inset) * index / 10, rect.center.dy);
    }

    testWidgets('the nearest thumb follows the finger, never past the other', (tester) async {
      await pump(tester);

      // A tap moves the nearest thumb there.
      await tester.tapAt(at(tester, 9));
      await tester.pump();
      expect(values, (2, 9));

      // Dragging the start thumb.
      await tester.dragFrom(at(tester, 2), at(tester, 5) - at(tester, 2));
      await tester.pump();
      expect(values, (5, 9));

      // It stops at the end thumb.
      await tester.dragFrom(at(tester, 5), at(tester, 10) - at(tester, 5));
      await tester.pump();
      expect(values, (9, 9));

      // Both at one place: the direction of the drag chooses (left: the start thumb).
      await tester.dragFrom(at(tester, 9), at(tester, 4) - at(tester, 9));
      await tester.pump();
      expect(values, (4, 9));
    });

    testWidgets('remote: Left / Right move the active thumb, OK switches to the other one', (tester) async {
      await pump(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(values, (1, 8));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(values, (2, 8));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      // Stopped at the end of the track.
      expect(values, (2, 10));
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
      }
      // Stopped at the start thumb.
      expect(values, (2, 2));
    });

    testWidgets('« Appliquer » returns the positions, « Réinitialiser » both ends', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      (int, int)? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildVixeoTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showVxRange(
                  context,
                  title: 'Années',
                  count: 11,
                  selected: (3, 7),
                  valueLabel: (i) => '${2000 + i}',
                  summary: (a, b) => '${2000 + a}–${2000 + b}',
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('2003–2007'), findsOneWidget);
      // The ends of the track.
      expect(find.text('2000'), findsOneWidget);
      expect(find.text('2010'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('2004–2007'), findsOneWidget);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(result, (4, 7));

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réinitialiser'));
      await tester.pump();
      expect(find.text('2000–2010'), findsOneWidget);
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      expect(result, (0, 10));
    });
  });
}
