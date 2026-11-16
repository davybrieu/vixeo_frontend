import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router.dart';
import '../auth/session.dart';
import '../library/library.dart';
import 'episode_alerts.dart';
import 'system_notifications.dart';

/// TV show ids of « Ma liste », as a key: the alerts are programmed again when it changes.
final _favoriteShowsKeyProvider = Provider<String>(
  (ref) => favoriteShowIds(ref.watch(libraryProvider).value ?? const LibraryState({})).join(','),
);

/// Around the app (`MaterialApp.builder`), like UpdateGate: prepares the notifications, opens the
/// page of a tapped notification (also one that launched the app), and programs the new-episode
/// alerts at launch, back in the foreground (once an hour at most) and when « Ma liste », the
/// profile or the setting changes. Nothing in a browser.
class NotificationsGate extends ConsumerStatefulWidget {
  const NotificationsGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationsGate> createState() => _NotificationsGateState();
}

class _NotificationsGateState extends ConsumerState<NotificationsGate> {
  late final bool _supported = ref.read(systemNotificationsProvider).supported;
  AppLifecycleListener? _lifecycle;
  DateTime? _synced;

  @override
  void initState() {
    super.initState();
    if (!_supported) return;
    _lifecycle = AppLifecycleListener(onResume: _syncIfStale);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final notifications = ref.read(systemNotificationsProvider);
    await notifications.init(_open);
    final path = await notifications.launchPath();
    if (path != null) _open(path);
  }

  /// A notification's page. Before the session is ready, the router keeps it and opens it once
  /// a profile is chosen.
  void _open(String path) {
    if (!mounted) return;
    final router = ref.read(routerProvider);
    final session = ref.read(sessionProvider);
    if (session.status == SessionStatus.signedIn && session.profile != null) {
      router.push(path);
    } else {
      router.go(path);
    }
  }

  void _sync() {
    _synced = DateTime.now();
    ref.read(episodeAlertsSchedulerProvider).sync();
  }

  void _syncIfStale() {
    final last = _synced;
    if (last == null || DateTime.now().difference(last) > const Duration(hours: 1)) _sync();
  }

  @override
  Widget build(BuildContext context) {
    if (_supported) {
      ref.listen(episodeAlertsSettingProvider, (previous, next) {
        if (next.hasValue && previous?.value != next.value) _sync();
      });
      ref.listen(_favoriteShowsKeyProvider, (previous, next) {
        if (previous != next) _sync();
      });
    }
    return widget.child;
  }
}
