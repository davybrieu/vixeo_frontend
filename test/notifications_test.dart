import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/local_store.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/library/library.dart';
import 'package:vixeo/features/notifications/episode_alerts.dart';
import 'package:vixeo/features/notifications/notifications_screen.dart';
import 'package:vixeo/features/notifications/system_notifications.dart';

/// The device's notifications, in memory.
class FakeNotifications implements SystemNotifications {
  FakeNotifications({this.supported = true, this.isAllowed = false, this.grant = true});

  @override
  final bool supported;
  bool isAllowed;
  bool grant;
  int permissionAsks = 0;
  bool settingsOpened = false;
  final shown = <LocalNotification>[];
  final schedules = <List<LocalNotification>>[];

  @override
  Future<void> init(void Function(String path) onOpen) async {}

  @override
  Future<String?> launchPath() async => null;

  @override
  Future<bool> allowed() async => isAllowed;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return isAllowed = grant;
  }

  @override
  Future<void> show(LocalNotification notification) async => shown.add(notification);

  @override
  Future<void> schedule(List<LocalNotification> notifications) async => schedules.add(notifications);

  @override
  Future<void> openSettings() async => settingsOpened = true;
}

/// `/catalog/episodes/upcoming`, recorded.
class UpcomingApi extends ApiClient {
  UpcomingApi(this.episodes) : super(token: () => 't', profileId: () => 1);

  final List<Map<String, dynamic>> episodes;
  final asked = <String>[];

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query, Duration? receiveTimeout}) async {
    asked.add('$path?ids=${query?['ids']}');
    return {'data': episodes};
  }
}

/// « Ma liste »: Lupin and a movie; Game of Thrones only watched.
class ShowsLibrary extends LibraryController {
  @override
  Future<LibraryState> build() async => LibraryState({
    'tmdb|tv:100088': ProfileItem(
      source: 'tmdb',
      itemId: 'tv:100088',
      type: 'tv',
      title: 'Lupin',
      isFavorite: true,
      favoritedAt: DateTime(2026, 11, 10),
    ),
    'tmdb|movie:550': ProfileItem(
      source: 'tmdb',
      itemId: 'movie:550',
      type: 'movie',
      title: 'Fight Club',
      isFavorite: true,
      favoritedAt: DateTime(2026, 11, 12),
    ),
    'tmdb|tv:1399': const ProfileItem(source: 'tmdb', itemId: 'tv:1399', type: 'tv', title: 'Game of Thrones'),
  });
}

class SignedInSession extends SessionController {
  SignedInSession([this.status = SessionStatus.signedIn]);

  final SessionStatus status;

  @override
  SessionState build() => SessionState(
    status: status,
    token: 't',
    profile: status == SessionStatus.signedIn ? const Profile(id: 1, name: 'Davy') : null,
  );
}

/// Noon, [days] from now (out of the night: notified at that time).
DateTime noonIn(int days) {
  final day = DateTime.now().add(Duration(days: days));
  return DateTime(day.year, day.month, day.day, 12);
}

Map<String, dynamic> episodeJson(int showId, String show, int season, int number, DateTime at, {String? name}) => {
  'show_id': showId,
  'show_name': show,
  'poster_url': null,
  'season_number': season,
  'episode_number': number,
  'name': name ?? 'Épisode $number',
  'air_date': '2026-11-20',
  'available_at': at.toUtc().toIso8601String(),
  'still_url': null,
};

UpcomingEpisode episode(int showId, int season, int number, DateTime at, {String? name, String show = 'Lupin'}) =>
    UpcomingEpisode.fromJson(episodeJson(showId, show, season, number, at, name: name));

void main() {
  group('alerts', () {
    test('the night is moved to 08:00', () {
      expect(alertTime(DateTime(2026, 11, 18, 3)), DateTime(2026, 11, 18, 8));
      expect(alertTime(DateTime(2026, 11, 18, 23, 30)), DateTime(2026, 11, 19, 8));
      expect(alertTime(DateTime(2026, 11, 30, 23)), DateTime(2026, 12, 1, 8));
      expect(alertTime(DateTime(2026, 11, 18, 21)), DateTime(2026, 11, 18, 21));
    });

    test('a show’s episodes at the same time make one notification, the soonest first', () {
      final now = DateTime(2026, 11, 16, 10);
      final alerts = episodeAlerts([
        episode(1399, 2, 4, DateTime(2026, 11, 25, 21), show: 'Game of Thrones'),
        episode(100088, 1, 2, DateTime(2026, 11, 20, 9)),
        episode(100088, 1, 1, DateTime(2026, 11, 20, 9)),
        episode(1399, 2, 3, DateTime(2026, 11, 18, 21), name: 'Le Pont', show: 'Game of Thrones'),
        // Already out.
        episode(1399, 2, 2, DateTime(2026, 11, 16, 9), show: 'Game of Thrones'),
      ], now: now);

      expect([for (final a in alerts) a.showName], ['Game of Thrones', 'Lupin', 'Game of Thrones']);
      expect(alerts[0].body, 'S2 · É3 « Le Pont » est disponible.');
      expect(alerts[1].body, '2 nouveaux épisodes de la saison 1 sont disponibles.');
      expect(alerts[1].codes, 'S1 · É1 à É2');
      // TMDb's "Épisode 4" says nothing more than the number.
      expect(alerts[2].body, 'S2 · É4 est disponible.');
      expect(alerts[1].path, '/titre/tv/100088');

      final ids = {for (final a in alerts) a.id};
      expect(ids, hasLength(3));
      expect(ids, isNot(contains(testNotificationId)));
      // The same alert, the same id: programmed again, it replaces itself.
      expect(episodeAlerts([episode(100088, 1, 1, DateTime(2026, 11, 20, 9))], now: now).single.id, alerts[1].id);
    });

    test('dates in French', () {
      final now = DateTime(2026, 11, 16, 10);
      expect(alertDateLabel(DateTime(2026, 11, 16, 21), now: now), 'Aujourd’hui, 21:00');
      expect(alertDateLabel(DateTime(2026, 11, 17, 8), now: now), 'Demain, 08:00');
      expect(alertDateLabel(DateTime(2026, 11, 20, 8), now: now), 'Vendredi 20 novembre, 08:00');
      expect(alertDateLabel(DateTime(2026, 12, 1, 21, 5), now: now), 'Mardi 1er décembre, 21:05');
    });
  });

  group('scheduler', () {
    ProviderContainer container({
      required FakeNotifications notifications,
      required UpcomingApi api,
      bool enabled = true,
      SessionStatus status = SessionStatus.signedIn,
    }) {
      final store = MemoryLocalStore();
      if (enabled) store.values[EpisodeAlertsSetting.keyFor(1)] = '1';
      final c = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => SignedInSession(status)),
          libraryProvider.overrideWith(ShowsLibrary.new),
          apiClientProvider.overrideWithValue(api),
          systemNotificationsProvider.overrideWithValue(notifications),
          localStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('programs the coming episodes of the « Ma liste » shows', () async {
      final notifications = FakeNotifications();
      final at = noonIn(3);
      final api = UpcomingApi([
        episodeJson(100088, 'Lupin', 4, 1, at),
        episodeJson(100088, 'Lupin', 4, 2, at),
        episodeJson(100088, 'Lupin', 3, 9, noonIn(-1)),
      ]);
      final c = container(notifications: notifications, api: api);

      await c.read(episodeAlertsSchedulerProvider).sync();

      // TV shows of « Ma liste » only.
      expect(api.asked, ['/catalog/episodes/upcoming?ids=100088']);
      final programmed = notifications.schedules.single;
      expect(programmed, hasLength(1));
      expect(programmed.single.title, 'Lupin');
      expect(programmed.single.body, '2 nouveaux épisodes de la saison 4 sont disponibles.');
      expect(programmed.single.at, at);
      expect(programmed.single.path, '/titre/tv/100088');
    });

    test('alerts off: nothing programmed', () async {
      final notifications = FakeNotifications();
      final api = UpcomingApi([episodeJson(100088, 'Lupin', 4, 1, noonIn(3))]);
      final c = container(notifications: notifications, api: api, enabled: false);

      await c.read(episodeAlertsSchedulerProvider).sync();

      expect(api.asked, isEmpty);
      expect(notifications.schedules, [isEmpty]);
    });

    test('session not ready yet: what is programmed stays', () async {
      final notifications = FakeNotifications();
      final c = container(notifications: notifications, api: UpcomingApi([]), status: SessionStatus.restoring);

      await c.read(episodeAlertsSchedulerProvider).sync();

      expect(notifications.schedules, isEmpty);
    });
  });

  group('« Notifications » page', () {
    late MemoryLocalStore store;

    Future<void> pump(
      WidgetTester tester,
      FakeNotifications notifications, {
      List<Map<String, dynamic>>? episodes,
    }) async {
      tester.view.physicalSize = const Size(520, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store = MemoryLocalStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(SignedInSession.new),
            libraryProvider.overrideWith(ShowsLibrary.new),
            apiClientProvider.overrideWithValue(UpcomingApi(episodes ?? const [])),
            systemNotificationsProvider.overrideWithValue(notifications),
            localStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(theme: buildVixeoTheme(), home: const NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('in a browser: says where notifications are', (tester) async {
      await pump(tester, FakeNotifications(supported: false));

      expect(find.textContaining('disponibles dans l’appli Android'), findsOneWidget);
      expect(find.text('Nouveaux épisodes'), findsNothing);
    });

    testWidgets('refused by the system: stays off, says where to allow them', (tester) async {
      final notifications = FakeNotifications(grant: false);
      await pump(tester, notifications);

      await tester.tap(find.text('Nouveaux épisodes'));
      await tester.pumpAndSettle();

      expect(notifications.permissionAsks, 1);
      expect(store.values, isEmpty);
      expect(find.text('Autorisez les notifications de Vixeo dans les réglages de l’appareil.'), findsOneWidget);
      expect(find.text('Notifications bloquées'), findsOneWidget);
      await tester.tap(find.text('Ouvrir les réglages'));
      expect(notifications.settingsOpened, isTrue);
    });

    testWidgets('turned on: asks, keeps the setting, lists the coming alerts', (tester) async {
      final notifications = FakeNotifications();
      final at = noonIn(3);
      await pump(
        tester,
        notifications,
        episodes: [episodeJson(100088, 'Lupin', 4, 1, at), episodeJson(100088, 'Lupin', 4, 2, at)],
      );
      expect(find.text('Prochaines alertes'), findsNothing);

      await tester.tap(find.text('Nouveaux épisodes'));
      await tester.pumpAndSettle();

      expect(notifications.permissionAsks, 1);
      expect(store.values[EpisodeAlertsSetting.keyFor(1)], '1');
      expect(find.text('Alertes de nouveaux épisodes activées'), findsOneWidget);
      expect(find.text('Prochaines alertes'), findsOneWidget);
      expect(find.text('Lupin'), findsOneWidget);
      expect(find.text('S4 · É1 à É2'), findsOneWidget);
    });

    testWidgets('sends a test notification for a show of « Ma liste »', (tester) async {
      final notifications = FakeNotifications(isAllowed: true);
      await pump(tester, notifications);
      expect(find.text('Une notification d’exemple pour « Lupin ».'), findsOneWidget);

      await tester.tap(find.text('Envoyer une notification de test'));
      await tester.pumpAndSettle();

      expect(notifications.permissionAsks, 0);
      expect(notifications.shown.single.id, testNotificationId);
      expect(notifications.shown.single.title, 'Lupin');
      expect(notifications.shown.single.path, '/titre/tv/100088');
      expect(find.text('Notification de test envoyée'), findsOneWidget);
    });
  });
}
