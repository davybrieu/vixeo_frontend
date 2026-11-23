import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local_store.dart';
import '../auth/session.dart';

/// « Nouveaux épisodes » of the active profile on this device (off by default): kept on the
/// device and sent to the server with the app's registration (`PushRegistration`), which then
/// announces the new episodes of the profile's « À voir » shows here.
final episodeAlertsSettingProvider = AsyncNotifierProvider<EpisodeAlertsSetting, bool>(EpisodeAlertsSetting.new);

class EpisodeAlertsSetting extends AsyncNotifier<bool> {
  static String keyFor(int profileId) => 'vixeo.notifications.episodes.$profileId';

  @override
  Future<bool> build() async {
    final profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
    if (profileId == null) return false;
    try {
      return await ref.read(localStoreProvider).read(keyFor(profileId)) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> set(bool value) async {
    final profileId = ref.read(sessionProvider).profile?.id;
    if (profileId == null) return;
    state = AsyncData(value);
    try {
      await ref.read(localStoreProvider).write(keyFor(profileId), value ? '1' : null);
    } catch (_) {
      // Not kept (private browsing…): on for this launch only.
    }
  }
}

/// « Activité » of the active profile on this device (on by default; developer's request,
/// 21/11/2026): a push when a member follows the profile, asks to follow it, accepts its request
/// or likes one of its reviews. Kept on the device, sent with the registration (`social`).
final socialAlertsSettingProvider = AsyncNotifierProvider<SocialAlertsSetting, bool>(SocialAlertsSetting.new);

class SocialAlertsSetting extends AsyncNotifier<bool> {
  static String keyFor(int profileId) => 'vixeo.notifications.social.$profileId';

  @override
  Future<bool> build() async {
    final profileId = ref.watch(sessionProvider.select((s) => s.profile?.id));
    if (profileId == null) return true;
    try {
      return await ref.read(localStoreProvider).read(keyFor(profileId)) != '0';
    } catch (_) {
      return true;
    }
  }

  Future<void> set(bool value) async {
    final profileId = ref.read(sessionProvider).profile?.id;
    if (profileId == null) return;
    state = AsyncData(value);
    try {
      // Off is kept; on is the default.
      await ref.read(localStoreProvider).write(keyFor(profileId), value ? null : '0');
    } catch (_) {
      // Not kept: for this launch only.
    }
  }
}
