import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/realtime.dart';
import 'package:vixeo/core/local_store.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/core/widgets/focusable.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/notifications/episode_alerts.dart';
import 'package:vixeo/features/notifications/notifications_gate.dart';
import 'package:vixeo/features/notifications/notifications_screen.dart';
import 'package:vixeo/features/notifications/push_messaging.dart';
import 'package:vixeo/features/notifications/push_registration.dart';
import 'package:vixeo/features/notifications/system_notifications.dart';

import 'realtime_fakes.dart';

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

/// Firebase Cloud Messaging, in memory: [fid] null = no Firebase in this build.
class FakePush implements PushMessaging {
  FakePush({this.supported = true, this.fid = 'fid-1'});

  @override
  final bool supported;
  String? fid;
  final receivedController = StreamController<PushNotification>.broadcast();
  final openedController = StreamController<String>.broadcast();
  final changesController = StreamController<String>.broadcast();

  @override
  Future<String?> installationId() async => fid;

  @override
  Stream<String> get installationIdChanges => changesController.stream;

  @override
  Stream<PushNotification> get received => receivedController.stream;

  @override
  Stream<String> get opened => openedController.stream;

  @override
  Future<String?> launchPath() async => null;
}

/// The API's `/push/device`, recorded.
class PushApi extends ApiClient {
  PushApi({this.available = true, this.realtime = true, this.testAnswer}) : super(token: () => 't', profileId: () => 1);

  final bool available;
  final bool realtime;
  final Map<String, dynamic>? testAnswer;
  final registrations = <Map<String, dynamic>>[];
  int tests = 0;

  int counts = 0;

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query, Duration? receiveTimeout}) async {
    if (path == '/notifications/count') {
      counts++;
      return {'unread_count': 2};
    }
    expect(path, '/push/device');
    return {'data': null, 'available': available, 'realtime': realtime};
  }

  @override
  Future<Map<String, dynamic>> put(String path, {Object? body}) async {
    expect(path, '/push/device');
    registrations.add(Map<String, dynamic>.from(body! as Map));
    return {
      'data': {'id': 7, 'target': body['platform'] == 'windows' ? 'realtime' : 'fid'},
    };
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

    test('gives the installation ID, the setting and the time zone, once in a while', () async {
      final api = PushApi();
      final c = container(push: FakePush(), api: api);

      expect(await c.read(pushRegistrationProvider).sync(), isTrue);
      expect(api.registrations.single, {
        'platform': 'android',
        'fid': 'fid-1',
        'new_episodes': true,
        'social': true,
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

    test('« Activité » turned off on this device: the server sends no social push', () async {
      final api = PushApi();
      final c = container(push: FakePush(), api: api);
      await c.read(socialAlertsSettingProvider.future);
      await c.read(socialAlertsSettingProvider.notifier).set(false);

      await c.read(pushRegistrationProvider).sync();
      expect(api.registrations.single['social'], isFalse);
      expect(api.registrations.single['new_episodes'], isTrue);
    });

    test('Windows: registered for the real-time channel, without Firebase', () async {
      final api = PushApi();
      final store = MemoryLocalStore();
      final c = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(SignedInSession.new),
          apiClientProvider.overrideWithValue(api),
          pushMessagingProvider.overrideWithValue(FakePush(supported: false)),
          pushTransportProvider.overrideWithValue(PushTransport.realtime),
          localStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c.dispose);

      expect(await c.read(pushRegistrationProvider).sync(), isTrue);
      expect(api.registrations.single, {
        'platform': 'windows',
        'new_episodes': false,
        'social': true,
        'utc_offset': DateTime.now().timeZoneOffset.inMinutes,
      });
      // Its channel: private-push-devices.7.
      expect(c.read(pushDeviceProvider), 7);
    });

    test('nothing without an installation ID, a profile or a session', () async {
      final api = PushApi();
      Future<bool> sync(ProviderContainer c) => c.read(pushRegistrationProvider).sync();

      expect(await sync(container(push: FakePush(fid: null), api: api)), isFalse);
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
      Realtime? realtime,
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
            if (realtime != null) ...[
              realtimeProvider.overrideWithValue(realtime),
              pushTransportProvider.overrideWithValue(PushTransport.realtime),
            ],
          ],
          child: MaterialApp(
            theme: buildVixeoTheme(),
            home: const NotificationsGate(child: NotificationsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a Windows build without Reverb: one sentence', (tester) async {
      await pump(tester, FakeNotifications(supported: false), push: FakePush(supported: false));

      expect(find.text('Les notifications sont disponibles dans l’appli Android.'), findsOneWidget);
      expect(find.text('Nouveaux épisodes'), findsNothing);
    });

    testWidgets('on Windows: the same alerts, shown while Vixeo is open', (tester) async {
      final notifications = FakeNotifications(isAllowed: true);
      final socket = FakeSocket();
      final realtime = Realtime(
        endpoint: Uri.parse('wss://api.vixeo.test/app/key'),
        connect: (_) async => socket,
        authorize: (_, channel) async => 'signed $channel',
      );
      addTearDown(realtime.dispose);
      await pump(tester, notifications, push: FakePush(supported: false), realtime: realtime);

      expect(find.text('Sur Windows, les notifications arrivent tant que Vixeo est ouvert.'), findsOneWidget);
      expect(find.text('Nouveaux épisodes'), findsOneWidget);
      expect(api.registrations.single['platform'], 'windows');

      // The channel of its registration (id 7), open while the app runs.
      socket.server('pusher:connection_established', {'socket_id': '1.2'});
      await tester.pumpAndSettle();
      expect(socket.sent.last, {
        'event': 'pusher:subscribe',
        'data': {'auth': 'signed private-push-devices.7', 'channel': 'private-push-devices.7'},
      });

      socket.server('notification', {
        'title': 'Nouvel abonné',
        'body': 'Max (@max) vous suit.',
        'path': '/membre/max',
        'channel': 'social',
        'tag': null,
        'image': null,
      }, channel: 'private-push-devices.7');
      await tester.pumpAndSettle();

      final shown = notifications.shown.single;
      expect(shown.title, 'Nouvel abonné');
      expect(shown.path, '/membre/max');
      expect(shown.channel, NotificationChannel.social);
      // The badge of « Notifications » is read again.
      expect(api.counts, 1);
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
      await pump(tester, FakeNotifications(), push: FakePush(fid: null));

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

    testWidgets('« Activité »: on by default, turned off here and on the server', (tester) async {
      await pump(tester, FakeNotifications(isAllowed: true));
      expect(api.registrations.last['social'], isTrue);
      expect(
        find.byWidgetPredicate((w) => w is VxFocusable && w.semanticLabel == 'Activité, activé'),
        findsOneWidget,
      );

      await tester.tap(find.text('Activité'));
      await tester.pumpAndSettle();
      expect(store.values[SocialAlertsSetting.keyFor(1)], '0');
      expect(find.text('Alertes d’activité désactivées'), findsOneWidget);
      expect(api.registrations.last['social'], isFalse);
    });

    testWidgets('a push of the activity reads the badge again', (tester) async {
      final notifications = FakeNotifications(isAllowed: true);
      final push = FakePush();
      await pump(tester, notifications, push: push);
      expect(api.counts, 0);

      push.receivedController.add(
        const PushNotification(title: 'Nouvel abonné', body: 'Max (@max) vous suit.', path: '/membre/max', channel: 'social'),
      );
      await tester.pumpAndSettle();

      expect(notifications.shown.single.channel, NotificationChannel.social);
      expect(api.counts, 1);
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
