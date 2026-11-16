import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

/// A notification shown now, or at [at]. A tap opens [path] (a page of the app).
class LocalNotification {
  const LocalNotification({required this.id, required this.title, required this.body, required this.path, this.at});

  final int id;
  final String title;
  final String body;
  final String path;
  final DateTime? at;
}

/// The device's notifications as Vixeo uses them: **local** notifications, shown or programmed by
/// the app itself (no push server, nothing registered with the API). Android (iOS ready, no app
/// yet); not in a browser, which can't program a notification. A fake in tests.
abstract class SystemNotifications {
  /// False in a browser: the page says so and nothing is programmed.
  bool get supported;

  /// Prepares the notifications; [onOpen] receives the page of a notification the person taps.
  Future<void> init(void Function(String path) onOpen);

  /// The page of the notification that launched the app, once (null afterwards).
  Future<String?> launchPath();

  /// Allowed by the system (Android: « Notifications » of the app in the settings).
  Future<bool> allowed();

  /// Android 13+: the system's question. True if allowed afterwards.
  Future<bool> requestPermission();

  Future<void> show(LocalNotification notification);

  /// Replaces every programmed notification with [notifications] (already shown ones stay).
  Future<void> schedule(List<LocalNotification> notifications);

  /// The system page of the app's notifications.
  Future<void> openSettings();
}

/// flutter_local_notifications. Every call is guarded: notifications never break the app.
class PluginNotifications implements SystemNotifications {
  PluginNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;
  void Function(String path)? _onOpen;
  bool _launchRead = false;

  /// Android channel (« Nouveaux épisodes » in the app's notification settings).
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'episodes',
      'Nouveaux épisodes',
      channelDescription: 'Un nouvel épisode d’une série de Ma liste est disponible.',
      // Vixeo green (VxColors.accent), behind the small icon.
      color: Color(0xFF2EE58A),
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  Future<bool> _ensure() => _ready ??= _initialize();

  Future<bool> _initialize() async {
    if (!supported) return false;
    try {
      return await _plugin.initialize(
            settings: const InitializationSettings(
              // White V of the logo (android/app/src/main/res/drawable/ic_notification.xml).
              android: AndroidInitializationSettings('ic_notification'),
              // The question is asked when the person turns the alerts on, not at launch.
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
            onDidReceiveNotificationResponse: (response) {
              final path = response.payload;
              if (path != null && path.startsWith('/')) _onOpen?.call(path);
            },
          ) ??
          false;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
      return false;
    }
  }

  Future<T> _guard<T>(Future<T> Function() call, T fallback) async {
    if (!await _ensure()) return fallback;
    try {
      return await call();
    } catch (e) {
      debugPrint('Notification call failed: $e');
      return fallback;
    }
  }

  @override
  Future<void> init(void Function(String path) onOpen) async {
    _onOpen = onOpen;
    await _ensure();
  }

  @override
  Future<String?> launchPath() async {
    if (_launchRead) return null;
    _launchRead = true;
    return _guard(() async {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final path = details?.didNotificationLaunchApp == true ? details?.notificationResponse?.payload : null;
      return path != null && path.startsWith('/') ? path : null;
    }, null);
  }

  @override
  Future<bool> allowed() => _guard(() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await _ios?.checkPermissions())?.isEnabled ?? false;
    }
    return await _android?.areNotificationsEnabled() ?? false;
  }, false);

  @override
  Future<bool> requestPermission() => _guard(() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    // Before Android 13 there is no question: the answer is the current state.
    await _android?.requestNotificationsPermission();
    return await _android?.areNotificationsEnabled() ?? false;
  }, false);

  @override
  Future<void> show(LocalNotification n) => _guard(
    () => _plugin.show(id: n.id, title: n.title, body: n.body, notificationDetails: _details, payload: n.path),
    null,
  );

  @override
  Future<void> schedule(List<LocalNotification> notifications) => _guard(() async {
    await _plugin.cancelAllPendingNotifications();
    final now = DateTime.now();
    for (final n in notifications) {
      final at = n.at;
      if (at == null || !at.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        payload: n.path,
        // An instant: UTC is enough (the device's time zone is already applied to [at]).
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: _details,
        // No "exact alarm" permission: Android may delay it by a few minutes.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }, null);

  @override
  Future<void> openSettings() => _guard(() => _plugin.openAppNotificationSettings(), null);
}

final systemNotificationsProvider = Provider<SystemNotifications>((ref) => PluginNotifications());
