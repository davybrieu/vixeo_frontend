import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Android notification channels of Vixeo (the server's `channel_id`, docs/notifications.md):
/// each one can be turned off in the app's notification settings of the device.
enum NotificationChannel {
  episodes('episodes', 'Nouveaux épisodes', 'Un nouvel épisode d’une série « À voir » est sorti.'),
  social('social', 'Activité', 'Messages, nouveaux abonnés, demandes d’abonnement et J’aime sur vos avis.'),
  general('general', 'Informations', 'Les messages de Vixeo.');

  const NotificationChannel(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  static NotificationChannel of(String? id) =>
      values.firstWhere((channel) => channel.id == id, orElse: () => NotificationChannel.general);
}

/// A notification shown by the app itself: a push received while Vixeo is open (Android only
/// shows those of a closed app), or one of the real-time channel (Windows). A tap opens [path] (a
/// page of the app).
class LocalNotification {
  const LocalNotification({
    required this.id,
    required this.title,
    required this.body,
    this.path,
    this.channel = NotificationChannel.general,
  });

  final int id;
  final String title;
  final String body;
  final String? path;
  final NotificationChannel channel;
}

/// The device's notification system: channels, the system's permission, a notification shown
/// while the app is open, and the page of a tapped one. The notifications themselves come from
/// the server (push, `push_messaging.dart`; on Windows the real-time channel). Android, Windows
/// (toasts) and iOS (ready, no app yet). A fake in tests.
abstract class SystemNotifications {
  /// False elsewhere (Linux, macOS: no Vixeo app there).
  bool get supported;

  /// Prepares the channels; [onOpen] receives the page of a notification shown by the app and
  /// tapped.
  Future<void> init(void Function(String path) onOpen);

  /// The page of the notification (shown by the app) that launched it, once (null afterwards).
  Future<String?> launchPath();

  /// Allowed by the system (Android: « Notifications » of the app in the settings).
  Future<bool> allowed();

  /// Android 13+: the system's question. True if allowed afterwards.
  Future<bool> requestPermission();

  Future<void> show(LocalNotification notification);

  /// The system page of the app's notifications.
  Future<void> openSettings();
}

/// flutter_local_notifications. Every call is guarded: notifications never break the app. On
/// Windows, toasts of an app installed without MSIX (Inno Setup): the plugin registers Vixeo for
/// them under [windowsAppId] (registry of the user, removed by the uninstaller,
/// windows/installer/vixeo.iss); a click brings the window to the front.
class PluginNotifications implements SystemNotifications {
  PluginNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;
  void Function(String path)? _onOpen;
  bool _launchRead = false;

  /// AppUserModelID of Vixeo on Windows (never change it: Windows keeps the notification settings
  /// of the app by it).
  static const windowsAppId = 'Vixeo.Vixeo';

  /// Activation of a clicked toast (COM class registered by the plugin; never change it either).
  static const windowsActivator = '27b7b264-7a02-4694-b923-e79cb2e4f440';

  static bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

  static NotificationDetails _details(NotificationChannel channel) => NotificationDetails(
    android: AndroidNotificationDetails(
      channel.id,
      channel.label,
      channelDescription: channel.description,
      importance: Importance.high,
      priority: Priority.high,
      // Vixeo green (VxColors.accent), behind the small icon.
      color: const Color(0xFF2EE58A),
    ),
    iOS: const DarwinNotificationDetails(),
  );

  @override
  bool get supported =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS || _windows;

  /// The app icon of the toasts: the PNG of the assets, next to vixeo.exe (null if missing).
  static String? _windowsIcon() {
    try {
      final folder = File(Platform.resolvedExecutable).parent.path;
      final icon = [folder, 'data', 'flutter_assets', 'assets', 'images', 'app_icon.png'].join(Platform.pathSeparator);
      return File(icon).existsSync() ? icon : null;
    } catch (_) {
      return null;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  Future<bool> _ensure() => _ready ??= _initialize();

  Future<bool> _initialize() async {
    if (!supported) return false;
    try {
      final ready =
          await _plugin.initialize(
            settings: InitializationSettings(
              // White V of the logo (android/app/src/main/res/drawable/ic_notification.xml).
              android: const AndroidInitializationSettings('ic_notification'),
              // The question is asked when the person turns the alerts on, not at launch.
              iOS: const DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
              windows: _windows
                  ? WindowsInitializationSettings(
                      appName: 'Vixeo',
                      appUserModelId: windowsAppId,
                      guid: windowsActivator,
                      iconPath: _windowsIcon(),
                    )
                  : null,
            ),
            onDidReceiveNotificationResponse: (response) {
              final path = response.payload;
              if (_windows) unawaited(_bringToFront());
              if (path != null && path.startsWith('/')) _onOpen?.call(path);
            },
          ) ??
          false;
      // The server's notifications name these channels: they must exist before the first one.
      for (final channel in NotificationChannel.values) {
        await _android?.createNotificationChannel(
          AndroidNotificationChannel(
            channel.id,
            channel.label,
            description: channel.description,
            importance: Importance.high,
          ),
        );
      }
      return ready;
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

  /// A clicked toast brings Vixeo's window to the front (it may be behind another, or minimised).
  static Future<void> _bringToFront() async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
  }

  @override
  Future<bool> allowed() => _guard(() async {
    // Windows has no permission to ask (the person turns them off in the system's settings).
    if (_windows) return true;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return (await _ios?.checkPermissions())?.isEnabled ?? false;
    }
    return await _android?.areNotificationsEnabled() ?? false;
  }, false);

  @override
  Future<bool> requestPermission() => _guard(() async {
    if (_windows) return true;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    // Before Android 13 there is no question: the answer is the current state.
    await _android?.requestNotificationsPermission();
    return await _android?.areNotificationsEnabled() ?? false;
  }, false);

  @override
  Future<void> show(LocalNotification n) => _guard(
    () => _plugin.show(
      id: n.id,
      title: n.title,
      body: n.body,
      notificationDetails: _details(n.channel),
      payload: n.path,
    ),
    null,
  );

  @override
  Future<void> openSettings() => _guard(() => _plugin.openAppNotificationSettings(), null);
}

final systemNotificationsProvider = Provider<SystemNotifications>((ref) => PluginNotifications());
