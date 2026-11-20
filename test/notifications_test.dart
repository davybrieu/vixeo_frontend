import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/local_store.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/notifications/episode_alerts.dart';
import 'package:vixeo/features/notifications/notifications_gate.dart';
import 'package:vixeo/features/notifications/notifications_screen.dart';
import 'package:vixeo/features/notifications/push_messaging.dart';
import 'package:vixeo/features/notifications/push_registration.dart';
import 'package:vixeo/features/notifications/system_notifications.dart';

/// The device's notification system, in memory.
class FakeNotifications implements SystemNotifications {
  FakeNotifications({this.supported = true, this.isAllowed = false, this.grant = true});

  @override
  final bool supported;
  bool isAllowed;
  bool grant;
  int permissionAsks = 0;
  bool settingsOpened = false;
  final shown = <LocalNotification>[];

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
  Future<void> openSettings() async => settingsOpened = true;
}

/// Firebase Cloud Messaging, in memory: [pushToken] null = no Firebase in this build.
class FakePush implements PushMessaging {
  FakePush({this.supported = true, this.pushToken = 'fcm-token'});

  @override
  final bool supported;
  String? pushToken;
  final receivedController = StreamController<PushNotification>.broadcast();
  final openedController = StreamController<String>.broadcast();
  final refreshController = StreamController<String>.broadcast();

  @override
  Future<String?> token() async => pushToken;

  @override
  Stream<String> get tokenRefresh => refreshController.stream;

  @override
  Stream<PushNotification> get received => receivedController.stream;

  @override
  Stream<String> get opened => openedController.stream;

  @override
  Future<String?> launchPath() async => null;
}

/// The API's `/push/device`, recorded.
class PushApi extends ApiClient {
  PushApi({this.available = true, this.testAnswer}) : super(token: () => 't', profileId: () => 1);

  final bool available;
  final Map<String, dynamic>? testAnswer;
  final registrations = <Map<String, dynamic>>[];
  int tests = 0;

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query, Duration? receiveTimeout}) async {
    expect(path, '/push/device');
    return {'data': null, 'available': available};
  }

  @override
  Future<Map<String, dynamic>> put(String path, {Object? body}) async {
    expect(path, '/push/device');
    registrations.add(Map<String, dynamic>.from(body! as Map));
    return {'data': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
    Duration? receiveTimeout,
  }) async {
    expect(path, '/push/device/test');
    tests++;
    return testAnswer ?? {'message': 'Notification de test envoyée.'};
  }
}

class SignedInSession extends SessionController {
  SignedInSession([this.status = SessionStatus.signedIn, this.withProfile = true]);

  final SessionStatus status;
  final bool withProfile;

  @override
  SessionState build() => SessionState(
    status: status,
    token: 't',
    profile: status == SessionStatus.signedIn && withProfile ? const Profile(id: 1, name: 'Davy') : null,
  );
}

void main() {
  group('registration with the server', () {
    ProviderContainer container({
      required FakePush push,
      required PushApi api,
      bool enabled = true,
      SessionController Function()? session,
    }) {
      final store = MemoryLocalStore();
      if (enabled) store.values[EpisodeAlertsSetting.keyFor(1)] = '1';
      final c = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(session ?? SignedInSession.new),
          apiClientProvider.overrideWithValue(api),
          pushMessagingProvider.overrideWithValue(push),
          localStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('gives the token, the setting and the time zone, once in a while', () async {
      final api = PushApi();
      final c = container(push: FakePush(), api: api);

      expect(await c.read(pushRegistrationProvider).sync(), isTrue);
      expect(api.registrations.single, {
        'token': 'fcm-token',
        'platform': 'android',
        'new_episodes': true,
        'utc_offset': DateTime.now().timeZoneOffset.inMinutes,
      });

      // Nothing new: not sent again (back in the foreground…), unless asked.
      await c.read(pushRegistrationProvider).sync();
      expect(api.registrations, hasLength(1));
      await c.read(pushRegistrationProvider).sync(force: true);
      expect(api.registrations, hasLength(2));
    });

    test('alerts off: registered all the same (messages of Vixeo), without the episodes', () async {
      final api = PushApi();
      final c = container(push: FakePush(), api: api, enabled: false);

      await c.read(pushRegistrationProvider).sync();
      expect(api.registrations.single['new_episodes'], isFalse);
    });

    test('nothing without a token, a profile or a session', () async {
      final api = PushApi();
      Future<bool> sync(ProviderContainer c) => c.read(pushRegistrationProvider).sync();

      expect(await sync(container(push: FakePush(pushToken: null), api: api)), isFalse);
      expect(
        await sync(
          container(push: FakePush(), api: api, session: () => SignedInSession(SessionStatus.signedIn, false)),
        ),
        isFalse,
      );
      expect(
        await sync(container(push: FakePush(), api: api, session: () => SignedInSession(SessionStatus.restoring))),
        isFalse,
      );
      expect(await sync(container(push: FakePush(supported: false), api: api)), isFalse);
      expect(api.registrations, isEmpty);
    });
  });

  group('« Notifications » page', () {
    late MemoryLocalStore store;
    late PushApi api;

    Future<void> pump(
      WidgetTester tester,
      FakeNotifications notifications, {
      FakePush? push,
      bool available = true,
    }) async {
      tester.view.physicalSize = const Size(520, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store = MemoryLocalStore();
      api = PushApi(available: available);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(SignedInSession.new),
            apiClientProvider.overrideWithValue(api),
            pushMessagingProvider.overrideWithValue(push ?? FakePush()),
            systemNotificationsProvider.overrideWithValue(notifications),
            localStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: const NotificationsGate(child: NotificationsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('on Windows: one sentence', (tester) async {
      await pump(tester, FakeNotifications(supported: false), push: FakePush(supported: false));

      expect(find.text('Les notifications sont disponibles dans l’appli Android.'), findsOneWidget);
      expect(find.text('Nouveaux épisodes'), findsNothing);
    });

    testWidgets('not available yet (server off): says so, nothing to turn on', (tester) async {
      final notifications = FakeNotifications();
      await pump(tester, notifications, available: false);

      expect(find.text('Le serveur n’envoie pas encore de notifications.'), findsOneWidget);
      await tester.tap(find.text('Nouveaux épisodes'));
      await tester.pumpAndSettle();
      expect(notifications.permissionAsks, 0);
      expect(store.values, isEmpty);
    });

    testWidgets('no Firebase in this build: says so too', (tester) async {
      await pump(tester, FakeNotifications(), push: FakePush(pushToken: null));

      expect(find.textContaining('Cette version de l’appli ne reçoit pas encore les notifications.'), findsOneWidget);
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

    testWidgets('turned on: asks, keeps the setting and tells the server', (tester) async {
      final notifications = FakeNotifications();
      await pump(tester, notifications);
      // Registered at launch, alerts off.
      expect(api.registrations.last['new_episodes'], isFalse);
      // No list of the coming alerts (developer's request).
      expect(find.text('Prochaines alertes'), findsNothing);

      await tester.tap(find.text('Nouveaux épisodes'));
      await tester.pumpAndSettle();

      expect(notifications.permissionAsks, 1);
      expect(store.values[EpisodeAlertsSetting.keyFor(1)], '1');
      expect(find.text('Alertes de nouveaux épisodes activées'), findsOneWidget);
      expect(api.registrations.last['new_episodes'], isTrue);
    });

    testWidgets('the server sends a test notification', (tester) async {
      await pump(tester, FakeNotifications(isAllowed: true));

      await tester.tap(find.text('Envoyer une notification de test'));
      await tester.pumpAndSettle();

      expect(api.tests, 1);
      expect(find.text('Notification de test envoyée.'), findsOneWidget);
    });

    testWidgets('a push received while the app is open is shown by the app', (tester) async {
      final notifications = FakeNotifications(isAllowed: true);
      final push = FakePush();
      await pump(tester, notifications, push: push);

      push.receivedController.add(
        const PushNotification(
          title: 'Lupin',
          body: '2 nouveaux épisodes de la saison 4 sont disponibles.',
          path: '/titre/tv/100088',
          channel: 'episodes',
        ),
      );
      await tester.pumpAndSettle();

      final shown = notifications.shown.single;
      expect(shown.title, 'Lupin');
      expect(shown.path, '/titre/tv/100088');
      expect(shown.channel, NotificationChannel.episodes);
    });
  });
}
