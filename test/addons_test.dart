import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/addons/addons.dart';
import 'package:vixeo/features/addons/addons_screen.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/playback/engine/engine_factory.dart';
import 'package:vixeo/features/playback/playback.dart';
import 'package:vixeo/features/playback/player_screen.dart';

import 'player_engine_test.dart' show FakeEngine, SignedOut, settle, closePlayer;
import 'tv_repository_test.dart' show RoutingAdapter;

/// Installed on the server for every account: no buttons.
const everyone = AddonInfo(
  id: '7',
  name: 'Pour tous',
  version: '1.0.0',
  host: 'shared.test',
  resources: ['stream'],
  types: ['movie', 'tv'],
  streams: true,
  shared: true,
);

AddonInfo own(String id, String name, {bool enabled = true, bool streams = true}) => AddonInfo(
  id: id,
  name: name,
  version: '2.0.0',
  host: '$id.test',
  resources: streams ? const ['stream'] : const ['catalog'],
  types: const ['movie'],
  streams: streams,
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
    addons = [for (final a in addons) a.id == id ? own(a.id, a.name, enabled: enabled) : a];
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
        'streams': true,
        'enabled': false,
        'shared': false,
        'adult': false,
      });
      expect(addon.id, '12');
      expect(addon.host, 'addon.test');
      expect(addon.enabled, isFalse);
      expect(addon.editable, isTrue);
      expect(addon.hasStreams, isTrue);
      expect(AddonInfo.fromJson({'id': '3', 'name': 'Tous', 'version': '1', 'shared': true}).editable, isFalse);
      // A plug-in installed when plug-ins could add catalogs: it gives no source.
      expect(
        AddonInfo.fromJson({'id': '4', 'name': 'Catalogue', 'version': '1', 'streams': false}).hasStreams,
        isFalse,
      );
      // An older API, without `streams`: read from the resources.
      expect(
        AddonInfo.fromJson({
          'id': '5',
          'name': 'Ancien',
          'version': '1',
          'resources': ['stream'],
        }).hasStreams,
        isTrue,
      );
    });

    test('leaves out the Vixeo catalog an older API still listed', () async {
      final adapter = RoutingAdapter([
        (
          '/addons',
          {
            'data': [
              {'id': 'vixeo', 'name': 'Vixeo', 'version': '1.0.0', 'built_in': true},
              {'id': '12', 'name': 'Films libres', 'version': '2.1.0', 'built_in': false, 'streams': true},
            ],
          },
          200,
        ),
      ]);
      final repository = AddonsRepository(
        ApiClient(
          token: () => 't',
          profileId: () => null,
          dio: Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter,
        ),
      );

      expect([for (final a in await repository.list()) a.id], ['12']);
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
    testWidgets('sources only: those of every account without buttons, the account’s own ones with theirs', (
      tester,
    ) async {
      await openAddons(
        tester,
        FakeAddons([
          everyone,
          own('1', 'Premier'),
          own('2', 'Second', enabled: false),
          own('3', 'Catalogue', streams: false),
        ]),
      );

      expect(find.text('Plug-ins'), findsOneWidget);
      expect(find.textContaining('Le catalogue ne change pas.'), findsOneWidget);
      expect(find.textContaining('catalogue Vixeo'), findsNothing);
      expect(find.textContaining('Copier'), findsNothing);

      expect(find.text('Pour tous les comptes · shared.test'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirer : Pour tous'), findsNothing);
      expect(find.bySemanticsLabel('Désactiver : Pour tous'), findsNothing);

      expect(find.text('1.test'), findsOneWidget);
      expect(find.text('Désactivé · 2.test'), findsOneWidget);
      // Installed when plug-ins could add catalogs: it gives no source, it can be removed.
      expect(find.text('Aucune source · 3.test'), findsOneWidget);
      expect(find.bySemanticsLabel('Désactiver : Premier'), findsOneWidget);
      expect(find.bySemanticsLabel('Activer : Second'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirer : Premier'), findsOneWidget);
      expect(find.bySemanticsLabel('Retirer : Catalogue'), findsOneWidget);
    });

    testWidgets('installs a plug-in from its address, and says why one is refused', (tester) async {
      final fake = await openAddons(tester, FakeAddons([everyone])..refuse = const ApiException(
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
      final fake = await openAddons(tester, FakeAddons([everyone, own('1', 'Premier'), own('2', 'Second')]));

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
