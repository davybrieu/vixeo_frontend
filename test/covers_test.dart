import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/profiles/covers.dart';

// The covers of the catalog are drawn by the app (vixeo_backend/docs/social.md): every pattern
// paints at a phone's and a TV's size, without an error.

const _colors = [Color(0xFF0D0221), Color(0xFF541388), Color(0xFFFF6B9D), Color(0xFF2DE2E6)];

final _styles = [
  CoverStyle(
    id: 'all',
    name: 'Tous',
    covers: [
      for (final pattern in CoverPattern.values)
        CoverDef(id: pattern.name, name: pattern.name, pattern: pattern, colors: _colors, angle: 160),
    ],
  ),
];

void main() {
  for (final size in const [Size(390, 130), Size(1500, 340)]) {
    testWidgets('every pattern paints at ${size.width.toInt()} × ${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = Size(size.width, size.height * CoverPattern.values.length);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [coverCatalogProvider.overrideWith((ref) async => _styles)],
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: Column(
              children: [
                for (final pattern in CoverPattern.values)
                  SizedBox.fromSize(size: size, child: ProfileCover(coverId: pattern.name)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<CoverPainter>()
          .map((p) => p.cover.pattern)
          .toList();
      expect(painters, CoverPattern.values);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no cover (an older API) or an unknown one: the green of the app; loading: nothing drawn', (
    tester,
  ) async {
    final container = ProviderContainer(overrides: [coverCatalogProvider.overrideWith((ref) async => _styles)]);
    addTearDown(container.dispose);
    // While the catalog loads.
    expect(container.read(coverByIdProvider('neon')), isNull);
    expect(container.read(coverByIdProvider(null)), CoverDef.fallback);
    await container.read(coverCatalogProvider.future);
    expect(container.read(coverByIdProvider('stars'))?.pattern, CoverPattern.stars);
    expect(container.read(coverByIdProvider('inconnue')), CoverDef.fallback);
  });
}
