import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/catalog/catalog_repository.dart';
import 'package:vixeo/features/catalog/models.dart';
import 'package:vixeo/features/library/actions.dart';
import 'package:vixeo/features/library/favorites_screen.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/shell/app_shell.dart';
import 'package:vixeo/features/tv/models.dart';

/// The sync API: a pull returns nothing, a push answers each change merged (`liked` → is_liked).
class SyncAdapter implements HttpClientAdapter {
  final pushed = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancel) async {
    Object body = {'data': [], 'cursor': 0, 'has_more': false};
    if (options.method == 'POST') {
      final changes = ((options.data as Map)['changes'] as List).cast<Map<String, dynamic>>();
      pushed.addAll(changes);
      body = {
        'data': [
          for (final c in changes)
            {
              ...c,
              'is_liked': (c['liked'] as Map?)?['value'] ?? false,
              'liked_at': (c['liked'] as Map?)?['at'],
              'is_favorite': false,
              'position_ms': 0,
              'is_watched': false,
            },
        ],
        'revision': pushed.length,
      };
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class SignedIn extends SessionController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.signedIn,
    token: 't',
    profile: Profile(id: 2, name: 'Léa'),
  );
}

ProviderContainer containerWith(SyncAdapter adapter) {
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(SignedIn.new),
      apiClientProvider.overrideWithValue(
        ApiClient(
          token: () => 't',
          profileId: () => 2,
          dio: Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))..httpClientAdapter = adapter,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

const show = MediaItem(id: 1399, type: MediaType.tv, title: 'Game of Thrones', backdropUrl: 'https://img.test/b.jpg');
const episode = Episode(
  id: 63056,
  seasonNumber: 1,
  number: 3,
  name: 'Lord Snow',
  stillUrl: 'https://img.test/still.jpg',
);
const channel = TvChannel(id: 'tf1', name: 'TF1', categoryId: 'Généralistes', logo: 'https://img.test/tf1.png');

/// « Favoris » (❤), separate from « Ma liste » (developer's request): movies, TV shows, episodes and
/// live channels, synced with the API's `liked` group.
void main() {
  test('reads is_liked, apart from Ma liste, and points back to a channel', () {
    final item = ProfileItem.fromJson({
      'source': 'tv',
      'item_id': 'channel:tf1',
      'type': 'channel',
      'title': 'TF1',
      'poster_url': 'https://img.test/tf1.png',
      'is_favorite': false,
      'is_liked': true,
      'liked_at': '2026-11-10T10:00:00Z',
    });
    expect(item.isLiked, isTrue);
    expect(item.isFavorite, isFalse);
    expect(item.likedAt, DateTime.utc(2026, 11, 10, 10));
    expect(item.asChannel?.id, 'tf1');
    expect(item.asChannel?.logo, 'https://img.test/tf1.png');
  });

  test('likes a movie, an episode and a channel through the sync', () async {
    final adapter = SyncAdapter();
    final container = containerWith(adapter);
    final library = container.read(libraryProvider.notifier);
    await container.read(libraryProvider.future);

    await library.setLiked(const MediaItem(id: 550, type: MediaType.movie, title: 'Fight Club'), true);
    await library.setEpisodeLiked(show, episode, true);
    await library.setChannelLiked(channel, true);

    expect(adapter.pushed.map((c) => (c['source'], c['item_id'], c['type'])), [
      ('tmdb', 'movie:550', 'movie'),
      ('tmdb', 'episode:1399:1:3', 'episode'),
      ('tv', 'channel:tf1', 'channel'),
    ]);
    expect(adapter.pushed.every((c) => (c['liked'] as Map)['value'] == true), isTrue);
    // Never the « Ma liste » group.
    expect(adapter.pushed.any((c) => c.containsKey('favorite')), isFalse);
    // An episode carries what the list shows: its show, numbers, still.
    expect(adapter.pushed[1], containsPair('parent_item_id', 'tv:1399'));
    expect(adapter.pushed[1], containsPair('season_number', 1));
    expect(adapter.pushed[1], containsPair('episode_number', 3));
    expect(adapter.pushed[1], containsPair('poster_url', 'https://img.test/still.jpg'));
    expect(adapter.pushed[2], containsPair('poster_url', 'https://img.test/tf1.png'));

    final state = container.read(libraryProvider).value!;
    expect(state.liked, hasLength(3));
    expect(state.forEpisode(1399, 1, 3)?.isLiked, isTrue);
    expect(state.forChannel(channel)?.isLiked, isTrue);

    await library.setChannelLiked(channel, false);
    expect(container.read(libraryProvider).value!.forChannel(channel)?.isLiked, isFalse);
    expect(container.read(libraryProvider).value!.liked, hasLength(2));
  });

  group('the « Favoris » page', () {
    final liked = {
      for (final item in [
        ProfileItem(
          source: 'tmdb',
          itemId: 'movie:550',
          type: 'movie',
          title: 'Fight Club',
          isLiked: true,
          likedAt: DateTime(2026, 11, 10, 4),
        ),
        ProfileItem(
          source: 'tmdb',
          itemId: 'tv:1399',
          type: 'tv',
          title: 'Game of Thrones',
          isLiked: true,
          likedAt: DateTime(2026, 11, 10, 3),
        ),
        ProfileItem(
          source: 'tmdb',
          itemId: 'episode:1399:1:3',
          type: 'episode',
          title: 'Lord Snow',
          parentItemId: 'tv:1399',
          seasonNumber: 1,
          episodeNumber: 3,
          isLiked: true,
          likedAt: DateTime(2026, 11, 10, 2),
        ),
        ProfileItem(
          source: 'tv',
          itemId: 'channel:tf1',
          type: 'channel',
          title: 'TF1',
          isLiked: true,
          likedAt: DateTime(2026, 11, 10, 1),
        ),
        // In « Ma liste » only: not a favorite.
        const ProfileItem(source: 'tmdb', itemId: 'movie:13', type: 'movie', title: 'Forrest Gump', isFavorite: true),
      ])
        item.key: item,
    };

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(SignedIn.new),
            libraryProvider.overrideWith(() => StaticLibrary(liked)),
            titlesByIdProvider.overrideWith((ref, key) async => {(type: MediaType.tv, id: 1399): show}),
          ],
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: const Scaffold(body: FavoritesScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('"Tout": a row per type, the episode with its show; « Ma liste » left out', (tester) async {
      await pump(tester);
      expect(find.text('Favoris'), findsOneWidget);
      expect(find.text('Films'), findsWidgets);
      expect(find.text('Séries'), findsWidgets);
      expect(find.text('Game of Thrones · S1 · É3'), findsOneWidget);
      expect(find.text('Lord Snow'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Forrest Gump')), findsNothing);

      final page = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
      await tester.scrollUntilVisible(find.text('TF1'), 200, scrollable: page);
      expect(find.text('TF1'), findsOneWidget);
    });

    testWidgets('a type filter and the search narrow the list', (tester) async {
      await pump(tester);
      await tapChip(tester, 'Chaînes TV');
      expect(find.text('TF1'), findsOneWidget);
      expect(find.text('Lord Snow'), findsNothing);

      await tapChip(tester, 'Épisodes');
      expect(find.text('Lord Snow'), findsOneWidget);

      // The show name matches its episodes too.
      await tester.enterText(find.byType(TextField), 'thrones');
      await tester.pumpAndSettle();
      expect(find.text('Lord Snow'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Aucun résultat'), findsOneWidget);
    });

    testWidgets('nothing loved yet: an invitation', (tester) async {
      liked.removeWhere((_, item) => item.isLiked);
      await pump(tester);
      expect(find.text('Aucun favori'), findsOneWidget);
    });
  });

  testWidgets('« Favoris » is a tab of the navigation, selected on its page (phone)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith(SignedIn.new)],
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: const AppShell(location: '/favoris', child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    // The tab bar is there, with the filled heart of the selected tab.
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
  });

  testWidgets('the heart button says what it does', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LikeButton(liked: false, onPressed: () => pressed++)),
      ),
    );
    expect(find.bySemanticsLabel('Ajouter aux favoris'), findsOneWidget);
    await tester.tap(find.byType(LikeButton));
    expect(pressed, 1);
  });
}

/// Taps a filter chip, scrolled into view first (the bar is wider than a phone).
Future<void> tapChip(WidgetTester tester, String label) async {
  final chip = find.text(label).first;
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// The library with fixed items, without the API.
class StaticLibrary extends LibraryController {
  StaticLibrary(this.items);

  final Map<String, ProfileItem> items;

  @override
  Future<LibraryState> build() async => LibraryState(Map.of(items));
}
