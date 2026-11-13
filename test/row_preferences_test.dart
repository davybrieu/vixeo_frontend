import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/profiles/row_preferences.dart';
import 'package:vixeo/features/profiles/rows_settings_screen.dart';

class FakeSession extends SessionController {
  @override
  SessionState build() =>
      const SessionState(status: SessionStatus.signedIn, token: 't', profile: Profile(id: 7, name: 'Davy'));
}

Section section(String key, String title) =>
    Section(key: key, title: title, type: MediaType.movie, list: 'popular', items: const []);

/// Order and visibility of the rows of the home page and of the « Chaînes TV » page (settings).
void main() {
  String same(String key) => key;

  test('rows keep their usual order and are all shown without a preference', () {
    expect(RowPreferences.none.visible(['a', 'b', 'c'], same), ['a', 'b', 'c']);
    expect(RowPreferences.none.isDefault, isTrue);
  });

  test('rows follow the chosen order; a row never placed comes after, a hidden one is left out', () {
    const preferences = RowPreferences(order: ['c', 'a'], hidden: {'a'});
    // The settings page lists them all, in order.
    expect(preferences.sorted(['a', 'b', 'c', 'd'], same), ['c', 'a', 'b', 'd']);
    expect(preferences.visible(['a', 'b', 'c', 'd'], same), ['c', 'b', 'd']);
    // A row that no longer exists is ignored.
    expect(const RowPreferences(order: ['gone', 'b']).visible(['a', 'b'], same), ['b', 'a']);
  });

  test('is written and read back; anything unreadable is the default', () {
    const preferences = RowPreferences(order: ['c', 'a'], hidden: {'a'});
    final read = RowPreferences.fromJson(preferences.toJson());
    expect(read.order, ['c', 'a']);
    expect(read.hidden, {'a'});
    expect(RowPreferences.fromJson(null).isDefault, isTrue);
    expect(RowPreferences.fromJson('not json').isDefault, isTrue);
    expect(RowPreferences.fromJson('[1]').isDefault, isTrue);
  });

  testWidgets('settings: move a home row down, hide another, reset', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = MemoryRowPreferencesStorage();
    final home = Home(
      featured: const [],
      sections: [section('movie_trending', 'Films du moment'), section('tv_popular', 'Séries populaires')],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(FakeSession.new),
          rowPreferencesStorageProvider.overrideWithValue(storage),
          homeProvider.overrideWith((ref) async => home),
        ],
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: const RowsSettingsScreen(page: RowsPage.home),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double y(String title) => tester.getCenter(find.text(title)).dy;
    expect(y('Films du moment'), lessThan(y('Séries populaires')));
    expect(find.text('Réinitialiser'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Descendre : Films du moment'));
    await tester.pumpAndSettle();
    expect(y('Séries populaires'), lessThan(y('Films du moment')));

    await tester.tap(find.bySemanticsLabel('Masquer : Séries populaires'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Afficher : Séries populaires'), findsOneWidget);

    // Kept on the device, for this profile.
    final saved = RowPreferences.fromJson(storage.values['vixeo.rows.home.7']);
    expect(saved.order, ['tv_popular', 'movie_trending']);
    expect(saved.hidden, {'tv_popular'});
    expect(saved.visible(home.sections, (s) => s.key).map((s) => s.title), ['Films du moment']);

    await tester.tap(find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    expect(storage.values, isEmpty);
    expect(y('Films du moment'), lessThan(y('Séries populaires')));
  });
}
