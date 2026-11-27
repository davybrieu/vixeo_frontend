import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import 'episode_alerts.dart';
import 'push_messaging.dart';

/// How this app receives the server's notifications (vixeo_backend/docs/notifications.md).
enum PushTransport {
  /// Firebase Cloud Messaging (Android, iOS): also when the app is closed.
  firebase,

  /// Windows has no Firebase: the real-time channel of its registration (`private-push-devices.{id}`,
  /// Reverb), while the app runs; the app shows them itself.
  realtime,

  /// None: a Windows build without a Reverb key.
  none,
}

final pushTransportProvider = Provider<PushTransport>((ref) {
  if (kIsWeb) return PushTransport.none;
  if (ref.watch(pushMessagingProvider).supported) return PushTransport.firebase;
  final realtime = ref.watch(realtimeProvider.select((r) => r.enabled));
  return defaultTargetPlatform == TargetPlatform.windows && realtime ? PushTransport.realtime : PushTransport.none;
});

/// The real-time channel of the push registration [id] (Windows).
String pushDeviceChannel(int id) => 'private-push-devices.$id';

/// Gives this app's Firebase installation ID to the server (`PUT /push/device`,
/// vixeo_backend/docs/notifications.md), or on Windows registers it for the real-time channel, with
/// the active profile (`X-Profile-Id`), its « Nouveaux épisodes » and « Activité » settings and the
/// device's time zone. The server then sends the notifications: nothing is programmed on the device.
/// Signing out removes the registration on the server (it belongs to the session's token).
class PushRegistration {
  PushRegistration(this._ref);

  final Ref _ref;
  Future<bool>? _running;
  String? _lastKey;
  DateTime? _lastAt;

  /// The same registration is sent again at most every 6 hours (it says the app is still used).
  static const refresh = Duration(hours: 6);

  /// One registration at a time. True when the server has this app's registration; false when
  /// it can't (no Firebase in this build, no Reverb key on Windows, signed out, no profile chosen,
  /// server down).
  Future<bool> sync({bool force = false}) {
    final next = (_running ?? Future.value(false)).then((_) => _run(force), onError: (_) => _run(force));
    _running = next;
    return next;
  }

  Future<bool> _run(bool force) async {
    final transport = _ref.read(pushTransportProvider);
    if (transport == PushTransport.none) return false;
    final session = _ref.read(sessionProvider);
    final profile = session.profile;
    if (session.status != SessionStatus.signedIn || profile == null) {
      _ref.read(pushDeviceProvider.notifier).set(null);
      return false;
    }
    try {
      String? fid;
      if (transport == PushTransport.firebase) {
        fid = await _ref.read(pushMessagingProvider).installationId();
        if (fid == null) return false;
      }
      final newEpisodes = await _ref.read(episodeAlertsSettingProvider.future);
      final social = await _ref.read(socialAlertsSettingProvider.future);
      final offset = DateTime.now().timeZoneOffset.inMinutes;
      final key = '${session.token}|${fid ?? transport.name}|${profile.id}|$newEpisodes|$social|$offset';
      final last = _lastAt;
      if (!force && key == _lastKey && last != null && DateTime.now().difference(last) < refresh) return true;

      final answer = await _ref.read(apiClientProvider).put(
        '/push/device',
        body: {
          'platform': switch (transport) {
            PushTransport.firebase => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
            _ => 'windows',
          },
          'fid': ?fid,
          'new_episodes': newEpisodes,
          // Followers, follow requests, likes of reviews, messages (vixeo_backend/docs/social.md).
          'social': social,
          'utc_offset': offset,
        },
      );
      final data = answer['data'];
      _ref.read(pushDeviceProvider.notifier).set(data is Map ? data['id'] as int? : null);
      _lastKey = key;
      _lastAt = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('Push registration failed: $e');
      return false;
    }
  }

  /// A test notification sent by the server to this app. Returns the server's message.
  Future<String> sendTest() async {
    if (!await sync(force: true)) {
      throw const PushUnavailable('Cet appareil ne peut pas recevoir de notifications pour le moment.');
    }
    final answer = await _ref.read(apiClientProvider).post('/push/device/test');
    return answer['message'] as String? ?? 'Notification de test envoyée.';
  }
}

class PushUnavailable implements Exception {
  const PushUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

final pushRegistrationProvider = Provider<PushRegistration>(PushRegistration.new);

/// The id of this app's registration on the server (its real-time channel, Windows); null when
/// not registered.
class PushDevice extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? id) => state = id;
}

final pushDeviceProvider = NotifierProvider<PushDevice, int?>(PushDevice.new);

/// The notifications of this app's real-time channel (Windows), while the app runs: listened to by
/// `NotificationsGate`, which shows them. Nothing for the other transports.
final realtimeNotificationsProvider = StreamProvider<PushNotification>((ref) {
  final id = ref.watch(pushDeviceProvider);
  if (id == null || ref.watch(pushTransportProvider) != PushTransport.realtime) return const Stream.empty();
  return ref
      .watch(realtimeProvider)
      .events(pushDeviceChannel(id))
      .where((event) => event.name == 'notification')
      .map((event) => PushNotification.fromRealtime(event.data));
});

/// Can this app receive notifications? (« Notifications » page.)
enum PushAvailability {
  ready,

  /// No way to receive them (a Windows build without a Reverb key).
  unsupported,

  /// This build has no Firebase project, or Google Play services are missing.
  noToken,

  /// The server sends no notification (not configured).
  serverOff,
}

final pushAvailabilityProvider = FutureProvider.autoDispose<PushAvailability>((ref) async {
  final transport = ref.read(pushTransportProvider);
  if (transport == PushTransport.none) return PushAvailability.unsupported;
  if (transport == PushTransport.firebase && await ref.read(pushMessagingProvider).installationId() == null) {
    return PushAvailability.noToken;
  }
  try {
    final answer = await ref.read(apiClientProvider).get('/push/device');
    // `available`: Firebase is configured on the server; `realtime`: Reverb is.
    final on = answer[transport == PushTransport.realtime ? 'realtime' : 'available'];
    return on == false ? PushAvailability.serverOff : PushAvailability.ready;
  } catch (_) {
    // Server unreachable: try anyway (the test says what goes wrong).
    return PushAvailability.ready;
  }
});
