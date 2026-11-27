import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/artwork.dart';
import 'package:vixeo/features/catalog/artwork_screen.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';

/// The API's answer for Dune (`GET /catalog/movie/438631/images`).
const _imagesJson = {
  'default': {
    'poster': '/default.jpg',
    'poster_url': 'https://image.tmdb.org/t/p/w342/default.jpg',
    'backdrop': '/b0.jpg',
    'backdrop_url': 'https://image.tmdb.org/t/p/w780/b0.jpg',
    'logo': '/l0.png',
    'logo_url': 'https://image.tmdb.org/t/p/w300/l0.png',
  },
  'chosen': {'poster': null, 'backdrop': null, 'logo': '/l1.png', 'logo_aspect_ratio': 4.2},
  'posters': [
    {'path': '/default.jpg', 'url': 'https://image.tmdb.org/t/p/w342/default.jpg', 'language': 'fr', 'aspect_ratio': 0.667},
    {'path': '/p1.jpg', 'url': 'https://image.tmdb.org/t/p/w342/p1.jpg', 'language': 'en', 'aspect_ratio': 0.667},
    {'path': '/p2.jpg', 'url': 'https://image.tmdb.org/t/p/w342/p2.jpg', 'language': null, 'aspect_ratio': 0.667},
  ],
  'backdrops': [
    {'path': '/b1.jpg', 'url': 'https://image.tmdb.org/t/p/w780/b1.jpg', 'language': null, 'aspect_ratio': 1.778},
  ],
  'logos': [
    {'path': '/l0.png', 'url': 'https://image.tmdb.org/t/p/w300/l0.png', 'language': 'fr', 'aspect_ratio': 2.5},
    {'path': '/l1.png', 'url': 'https://image.tmdb.org/t/p/w300/l1.png', 'language': 'en', 'aspect_ratio': 4.2},
  ],
};

class _Catalog extends CatalogRepository {
  _Catalog() : super(ApiClient(token: () => null));

  final choices = <String>[];

  @override
  Future<TitleImages> images(MediaType type, int id) async => TitleImages.fromJson(_imagesJson);

  @override
  Future<void> chooseImage(int profileId, MediaType type, int id, ArtworkKind kind, String? path) async =>
      choices.add('$profileId ${type.name}:$id ${kind.field} ${path ?? 'TMDb'}');
}

class _Signed extends SessionController {
  @override
  SessionState build() =>
      const SessionState(status: SessionStatus.signedIn, token: 't', profile: Profile(id: 7, name: 'Léa'));
}

void main() {
  test('reads the images of a title, TMDb’s choice and the profile’s', () {
    final images = TitleImages.fromJson(_imagesJson);
    expect(images.defaults[ArtworkKind.poster]?.path, '/default.jpg');
    expect(images.defaults[ArtworkKind.logo]?.url, 'https://image.tmdb.org/t/p/w300/l0.png');
    expect(images.chosen, {ArtworkKind.poster: null, ArtworkKind.backdrop: null, ArtworkKind.logo: '/l1.png'});
    expect([for (final image in images.images[ArtworkKind.poster]!) image.path], ['/default.jpg', '/p1.jpg', '/p2.jpg']);
    expect(images.images[ArtworkKind.logo]![1].aspectRatio, 4.2);
  });

  testWidgets('« Par défaut » first, a tap chooses at once, and the catalog is read again', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalog = _Catalog();
    final container = ProviderContainer(
      overrides: [catalogRepositoryProvider.overrideWithValue(catalog), sessionProvider.overrideWith(_Signed.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: const ArtworkScreen(type: MediaType.movie, id: 438631),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Posters: TMDb's is « Par défaut » (chosen), not offered a second time.
    expect(find.text('Affiches'), findsWidgets);
    expect(find.bySemanticsLabel('Par défaut, choisi'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Affiche \d')), findsNWidgets(2));

    await tester.tap(find.bySemanticsLabel('Affiche 2'));
    await tester.pumpAndSettle();
    expect(catalog.choices, ['7 movie:438631 poster /p2.jpg']);
    expect(find.bySemanticsLabel('Affiche 2, choisi'), findsOneWidget);
    expect(find.bySemanticsLabel('Par défaut'), findsOneWidget);
    // Every list, search and title page reads its images again.
    expect(container.read(catalogEpochProvider), 1);

    // Logos: the profile's is chosen; « Par défaut » goes back to TMDb's.
    await tester.tap(find.text('Logos'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Logo 1, choisi'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Par défaut'));
    await tester.pumpAndSettle();
    expect(catalog.choices.last, '7 movie:438631 logo TMDb');
    expect(find.bySemanticsLabel('Par défaut, choisi'), findsOneWidget);
  });
}
