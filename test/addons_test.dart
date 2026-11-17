import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/addons/addons.dart';
import 'package:vixeo/features/addons/addons_screen.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/home_screen.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/playback/engine/engine_factory.dart';
import 'package:vixeo/features/playback/playback.dart';
import 'package:vixeo/features/playback/player_screen.dart';

import 'home_tv_test.dart' show EmptyLibrary, movie;
import 'player_engine_test.dart' show FakeEngine, SignedOut, settle, closePlayer;

const vixeo = AddonInfo(
  id: 'vixeo',
  name: 'Vixeo',
  description: 'Le catalogue de Vixeo.',
  version: '1.0.0',
  resources: ['catalog', 'meta'],
  types: ['movie', 'tv'],
  catalogs: 14,
  builtIn: true,
  manifestUrl: 'https://api.vixeo.test/api/v1/addons/vixeo/manifest.json',
);

AddonInfo own(String id, String name, {bool enabled = true}) => AddonInfo(
  id: id,
  name: name,
  version: '2.0.0',
  host: '$id.test',
  resources: const ['catalog', 'stream'],
  types: const ['movie'],
  catalogs: 1,
  enabled: enabled,
);

/// The account's plug-ins without the API: what each button asked for is kept.
class FakeAddons extends AddonsRepository {
  FakeAddons(this.addons) : super(ApiClient(token: () => null, profileId: () => null));

  List<AddonInfo> addons;
  final installed = <String>[];
  final toggled = <(String, bool)>[];
  final orders = <List<String>>[];
  final removed = <String>[];
  ApiException? refuse;

  @override
  Future<List<AddonInfo>> list() async => addons;

  @override
  Future<AddonInfo> install(String url) async {
    if (refuse != null) throw refuse!;
    installed.add(url);
    final addon = own('new', 'Nouveau');
    addons = [...addons, addon];
    return addon;
  }

  @override
  Future<void> setEnabled(String id, {required bool enabled}) async {
    toggled.add((id, enabled));
    addons = [
      for (final a in addons)
        a.id == id
            ? AddonInfo(
                id: a.id,
                name: a.name,
                version: a.version,
                host: a.host,
                resources: a.resources,
                types: a.types,
                catalogs: a.catalogs,
                enabled: enabled,
                builtIn: a.builtIn,
                shared: a.shared,
                manifestUrl: a.manifestUrl,
              )
            : a,
    ];
  }

  @override
  Future<void> reorder(List<String> ids) async => orders.add(ids);

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    addons = [for (final a in addons) if (a.id != id) a];
  }
}

Future<FakeAddons> openAddons(WidgetTester tester, FakeAddons fake) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(SignedOut.new),
        addonsRepositoryProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(theme: buildVixeoTheme(), home: const AddonsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('models', () {
    test('reads a plug-in of the account', () {
      final addon = AddonInfo.fromJson({
        'id': '12',
        'name': 'Films libres',
        'description': null,
        'version': '2.1.0',
        'logo_url': 'https://addon.test/logo.png',
        'host': 'addon.test',
        'resources': ['catalog', 'stream'],
        'types': ['movie', 'tv'],
        'catalogs': 3,
        'enabled': false,
        'built_in': false,
        'shared': false,
        'adult': false,
        'manifest_url': null,
      });
      expect(addon.id, '12');
      expect(addon.host, 'addon.test');
      expect(addon.enabled, isFalse);
      expect(addon.editable, isTrue);
      expect(addon.hasStreams, isTrue);
      expect(addon.hasCatalogs, isTrue);
      expect(AddonInfo.fromJson({'id': 'vixeo', 'name': 'Vixeo', 'version': '1', 'built_in': true}).editable, isFalse);
      expect(AddonInfo.fromJson({'id': '3', 'name': 'Tous', 'version': '1', 'shared': true}).editable, isFalse);
    });

    test('reads a source already playable (a plug-in stream) with its headers', () {
      final source = StreamSource.fromJson({
        'provider': 'addon:12',
        'name': 'Films libres 1080p',
        'url': 'https://cdn.test/a.m3u8',
        'stream': 'https://cdn.test/a.m3u8',
        'stream_type': 'm3u8',
        'extractor': null,
        'headers': {'Referer': 'https://cdn.test/'},
      });
      expect(source.stream, 'https://cdn.test/a.m3u8');
      expect(source.streamType, 'm3u8');
      expect(source.headers, {'Referer': 'https://cdn.test/'});

      final link = StreamSource.fromJson({'provider': 'p', 'name': 'VF', 'url': 'https://host.test/e', 'stream': null});
      expect(link.stream, isNull);
      expect(link.headers, isEmpty);
    });
  });

  group('« Plug-ins »', () {
    testWidgets('Vixeo first; every plug-in can be turned off, only the own ones moved or removed', (
      tester,
    ) async {
      const shared = AddonInfo(id: '9', name: 'Pour tous', version: '1.0', shared: true, resources: ['stream']);
      await openAddons(tester, FakeAddons([vixeo, shared, own('1', 'Premier'), own('2', 'Second', enabled: false)]));

      expect(find.text('Plug-ins'), findsOneWidget);
      expect(find.textContaining('Par défaut'), findsOneWidget);
      expect(find.textContaining('14 catalogues'), findsOneWidget);
      expect(find.bySemanticsLabel('Copier l’adresse Stremio du catalogue Vixeo'), findsOneWidget);
      expect(find.bySemanticsLabel('Désactiver : Vixeo'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirer : Vixeo'), findsNothing);
      expect(find.bySemanticsLabel('Monter : Vixeo'), findsNothing);

      expect(find.textContaining('Pour tous les comptes'), findsOneWidget);
      expect(find.bySemanticsLabel('Désactiver : Pour tous'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirer : Pour tous'), findsNothing);

      expect(find.textContaining('1 catalogue · Sources · 1.test'), findsOneWidget);
      expect(find.textContaining('Désactivé'), findsOneWidget);
      expect(find.bySemanticsLabel('Désactiver : Premier'), findsOneWidget);
      expect(find.bySemanticsLabel('Activer : Second'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirer : Premier'), findsOneWidget);
    });

    testWidgets('turns the Vixeo catalog off and back on', (tester) async {
      final fake = await openAddons(tester, FakeAddons([vixeo]));

      await tester.tap(find.bySemanticsLabel('Désactiver : Vixeo'));
      await tester.pumpAndSettle();
      expect(fake.toggled, [('vixeo', false)]);
      expect(find.text('Plug-in désactivé'), findsOneWidget);
      expect(find.textContaining('Par défaut · Désactivé'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Activer : Vixeo'));
      await tester.pumpAndSettle();
      expect(fake.toggled.last, ('vixeo', true));
      expect(find.bySemanticsLabel('Désactiver : Vixeo'), findsOneWidget);
    });

    testWidgets('installs a plug-in from its address, and says why one is refused', (tester) async {
      final fake = await openAddons(tester, FakeAddons([vixeo])..refuse = const ApiException(
        'Les données sont invalides.',
        status: 422,
        fieldErrors: {
          'url': ['Cette adresse de plug-in n’est pas autorisée.'],
        },
      ));

      await tester.tap(find.text('Installer'));
      await tester.pumpAndSettle();
      expect(find.text('Collez l’adresse du plug-in.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'https://private.test/manifest.json');
      await tester.tap(find.text('Installer'));
      await tester.pumpAndSettle();
      expect(find.text('Cette adresse de plug-in n’est pas autorisée.'), findsOneWidget);

      fake.refuse = null;
      await tester.enterText(find.byType(TextField), '  https://addon.test/manifest.json ');
      await tester.tap(find.text('Installer'));
      await tester.pumpAndSettle();
      expect(fake.installed, ['https://addon.test/manifest.json']);
      expect(find.text('Plug-in installé : Nouveau'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirer : Nouveau'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('turns off, moves and removes the account’s own plug-ins', (tester) async {
      final fake = await openAddons(tester, FakeAddons([vixeo, own('1', 'Premier'), own('2', 'Second')]));

      await tester.tap(find.bySemanticsLabel('Désactiver : Premier'));
      await tester.pumpAndSettle();
      expect(fake.toggled, [('1', false)]);
      expect(find.text('Plug-in désactivé'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Monter : Second'));
      await tester.pumpAndSettle();
      expect(fake.orders, [
        ['2', '1'],
      ]);

      await tester.tap(find.bySemanticsLabel('Retirer : Second'));
      await tester.pumpAndSettle();
      expect(find.text('Retirer le plug-in'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();
      expect(fake.removed, isEmpty);

      await tester.tap(find.bySemanticsLabel('Retirer : Second'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer'));
      await tester.pumpAndSettle();
      expect(fake.removed, ['2']);
      expect(find.bySemanticsLabel('Retirer : Second'), findsNothing);
    });
  });

  group('rows of the home', () {
    Future<void> pumpPhoneHome(WidgetTester tester, {required List<Section> addonSections}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(SignedOut.new),
            // The Vixeo catalog turned off: the API gives an empty home.
            homeProvider.overrideWith((ref) async => const Home(featured: [], sections: [])),
            addonSectionsProvider.overrideWith((ref) async => addonSections),
            libraryProvider.overrideWith(EmptyLibrary.new),
            titlesByIdProvider.overrideWith((ref, key) async => const {}),
          ],
          child: MaterialApp(theme: buildVixeoTheme(), home: const Scaffold(body: HomeScreen())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('without the Vixeo catalog, the rows of the other plug-ins are the home', (tester) async {
      await pumpPhoneHome(
        tester,
        addonSections: [
          Section(
            key: 'movie_addon:12:top',
            title: 'Les meilleurs · Films libres',
            type: MediaType.movie,
            list: 'addon:12:top',
            items: [movie(550, 'Fight Club')],
          ),
        ],
      );

      expect(find.text('Les meilleurs · Films libres'), findsOneWidget);
      expect(find.text('Rien à afficher pour l’instant'), findsNothing);
    });

    testWidgets('nothing at all: « Rien à afficher »', (tester) async {
      await pumpPhoneHome(tester, addonSections: const []);

      expect(find.text('Rien à afficher pour l’instant'), findsOneWidget);
    });

    test('a failure of the plug-ins adds no row, it never breaks the home', () async {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(SignedOut.new),
          addonsRepositoryProvider.overrideWithValue(_FailingSections()),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(addonSectionsProvider, (_, _) {});
      addTearDown(sub.close);
      expect(await container.read(addonSectionsProvider.future), isEmpty);
    });
  });

  group('player', () {
    testWidgets('plays a plug-in stream as it is, with its headers, without asking the API to resolve it', (
      tester,
    ) async {
      final engine = FakeEngine();
      final playback = _NoResolve();
      const source = StreamSource(
        provider: 'addon:12',
        name: 'Films libres 1080p',
        url: 'https://cdn.test/fc.m3u8',
        stream: 'https://cdn.test/fc.m3u8',
        streamType: 'm3u8',
        headers: {'Referer': 'https://cdn.test/'},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(SignedOut.new),
            playbackRepositoryProvider.overrideWithValue(playback),
            playerEngineFactoryProvider.overrideWithValue((source) => engine),
            sourceProvidersProvider.overrideWith(
              (ref, item) async => const [SourceProvider(id: 'addon:12', name: 'Films libres')],
            ),
            providerSourcesProvider.overrideWith((ref, key) async => const [source]),
          ],
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: const PlayerScreen(type: MediaType.movie, id: 550),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Films libres'));
      await settle(tester);
      await tester.tap(find.text('Films libres 1080p'));
      await settle(tester);

      expect(playback.resolved, isEmpty);
      expect(engine.opened?.url, 'https://cdn.test/fc.m3u8');
      expect(engine.opened?.isHls, isTrue);
      expect(engine.opened?.headers, {'Referer': 'https://cdn.test/'});
      expect(engine.plays, 1);

      await closePlayer(tester);
    });
  });
}

class _FailingSections extends AddonsRepository {
  _FailingSections() : super(ApiClient(token: () => null, profileId: () => null));

  @override
  Future<List<Section>> sections() async => throw const ApiException('Une erreur est survenue (404).', status: 404);
}

/// Records the links it is asked to resolve: a plug-in stream must not be one.
class _NoResolve extends PlaybackRepository {
  _NoResolve() : super(ApiClient(token: () => null, profileId: () => null));

  final resolved = <String>[];

  @override
  Future<ResolvedStream> resolve(String url) async {
    resolved.add(url);
    throw const ApiException('Cette source n’est pas lisible.', status: 502);
  }

  @override
  Future<List<SubtitleOption>> subtitles(PlaybackItem item, {List<String>? languages}) async => const [];
}
