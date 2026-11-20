import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import 'episode_alerts.dart';
import 'push_messaging.dart';

/// Gives this app's push token to the server (`PUT /push/device`, vixeo_backend/docs/notifications.md)
/// with the active profile (`X-Profile-Id`), its « Nouveaux épisodes » setting and the device's
/// time zone. The server then sends the notifications: nothing is programmed on the device.
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
  /// it can't (Windows, no Firebase in this build, signed out, no profile chosen, server down).
  Future<bool> sync({bool force = false}) {
    final next = (_running ?? Future.value(false)).then((_) => _run(force), onError: (_) => _run(force));
    _running = next;
    return next;
  }

  Future<bool> _run(bool force) async {
    final messaging = _ref.read(pushMessagingProvider);
    if (!messaging.supported) return false;
    final session = _ref.read(sessionProvider);
    final profile = session.profile;
    if (session.status != SessionStatus.signedIn || profile == null) return false;
    try {
      final token = await messaging.token();
      if (token == null) return false;
      final newEpisodes = await _ref.read(episodeAlertsSettingProvider.future);
      final offset = DateTime.now().timeZoneOffset.inMinutes;
      final key = '${session.token}|$token|${profile.id}|$newEpisodes|$offset';
      final last = _lastAt;
      if (!force && key == _lastKey && last != null && DateTime.now().difference(last) < refresh) return true;

      await _ref.read(apiClientProvider).put(
        '/push/device',
        body: {
          'token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          'new_episodes': newEpisodes,
          'utc_offset': offset,
        },
      );
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

/// Can this app receive notifications? (« Notifications » page.)
enum PushAvailability {
  ready,

  /// Windows: no push.
  unsupported,

  /// This build has no Firebase project, or Google Play services are missing.
  noToken,

  /// The server sends no notification (not configured).
  serverOff,
}

final pushAvailabilityProvider = FutureProvider.autoDispose<PushAvailability>((ref) async {
  final messaging = ref.read(pushMessagingProvider);
  if (!messaging.supported) return PushAvailability.unsupported;
  if (await messaging.token() == null) return PushAvailability.noToken;
  try {
    final answer = await ref.read(apiClientProvider).get('/push/device');
    return answer['available'] == false ? PushAvailability.serverOff : PushAvailability.ready;
  } catch (_) {
    // Server unreachable: try anyway (the test says what goes wrong).
    return PushAvailability.ready;
  }
});
