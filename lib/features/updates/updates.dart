import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api/api_client.dart';
import '../auth/session.dart';

/// Platforms whose app checks for updates (vixeo_backend/docs/mise-a-jour.md). The web always
/// loads the latest version, so it doesn't check.
enum UpdatePlatform { android, ios }

/// Platform of this app for update checks, or null when it doesn't check (web, desktop).
///
/// Debug and profile builds can force one, to try the screens in a browser:
/// `--dart-define=UPDATE_PLATFORM=android`.
UpdatePlatform? currentUpdatePlatform() {
  const forced = String.fromEnvironment('UPDATE_PLATFORM');
  if (!kReleaseMode && forced.isNotEmpty) return UpdatePlatform.values.asNameMap()[forced];
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => UpdatePlatform.android,
    TargetPlatform.iOS => UpdatePlatform.ios,
    _ => null,
  };
}

/// The installed app: `version` and build number of pubspec.yaml (`1.2.0+14`), read from the
/// platform (CFBundleShortVersionString / CFBundleVersion, versionName / versionCode).
class InstalledVersion {
  const InstalledVersion({required this.version, required this.build});

  final String version;
  final int build;
}

enum UpdateStatus {
  upToDate,
  updateAvailable,
  updateRequired;

  static UpdateStatus parse(String? value) => switch (value) {
    'update_available' => UpdateStatus.updateAvailable,
    'update_required' => UpdateStatus.updateRequired,
    _ => UpdateStatus.upToDate,
  };
}

/// A published version (`latest` in `GET /app/update`).
class AppRelease {
  const AppRelease({required this.version, required this.build, this.notes, this.downloadUrl, this.sha256});

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    final notes = (json['notes'] as String? ?? '').trim();
    return AppRelease(
      version: json['version'] as String? ?? '',
      build: json['build'] as int? ?? 0,
      notes: notes.isEmpty ? null : notes,
      downloadUrl: json['download_url'] as String?,
      sha256: json['sha256'] as String?,
    );
  }

  final String version;
  final int build;

  /// What's new, in French.
  final String? notes;

  /// Android (no Play Store): the APK the app downloads and installs, and its SHA-256.
  final String? downloadUrl;
  final String? sha256;
}

/// Answer of `GET /app/update`.
class UpdateInfo {
  const UpdateInfo({required this.status, this.latest, this.updateUrl});

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    status: UpdateStatus.parse(json['status'] as String?),
    latest: json['latest'] is Map<String, dynamic> ? AppRelease.fromJson(json['latest'] as Map<String, dynamic>) : null,
    updateUrl: json['update_url'] as String?,
  );

  final UpdateStatus status;
  final AppRelease? latest;

  /// Install page of the site (no Play Store), when the app can't install the update itself.
  final String? updateUrl;
}

class UpdateRepository {
  UpdateRepository(this._api);

  final ApiClient _api;

  Future<UpdateInfo> check(UpdatePlatform platform, int build) async =>
      UpdateInfo.fromJson(await _api.get('/app/update', query: {'platform': platform.name, 'build': build}));
}

final updatePlatformProvider = Provider<UpdatePlatform?>((ref) => currentUpdatePlatform());

final installedVersionProvider = FutureProvider<InstalledVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return InstalledVersion(version: info.version, build: int.tryParse(info.buildNumber) ?? 0);
});

final updateRepositoryProvider = Provider<UpdateRepository>((ref) => UpdateRepository(ref.read(apiClientProvider)));

/// Last answer about updates: checked at launch, again when the app comes back to the foreground
/// after [staleAfter], or on demand ("Rechercher une mise à jour").
///
/// A failed check (offline, server down) never blocks the app: the state stays null.
class UpdateController extends AsyncNotifier<UpdateInfo?> {
  static const staleAfter = Duration(hours: 6);

  DateTime? _checkedAt;

  @override
  Future<UpdateInfo?> build() async {
    try {
      return await _fetch();
    } catch (_) {
      return null;
    }
  }

  /// Asks the API. Throws on failure (the "À propos" page shows it); null on a platform that
  /// doesn't check.
  Future<UpdateInfo?> check() async {
    final info = await _fetch();
    state = AsyncData(info);
    return info;
  }

  Future<UpdateInfo?> _fetch() async {
    final platform = ref.read(updatePlatformProvider);
    if (platform == null) return null;
    final installed = await ref.read(installedVersionProvider.future);
    final info = await ref.read(updateRepositoryProvider).check(platform, installed.build);
    _checkedAt = DateTime.now();
    return info;
  }

  /// Back to the foreground: checks again if the last answer is old.
  Future<void> checkIfStale() async {
    final checkedAt = _checkedAt;
    if (checkedAt != null && DateTime.now().difference(checkedAt) < staleAfter) return;
    try {
      await check();
    } catch (_) {
      // Offline: keep the previous answer.
    }
  }
}

final updateProvider = AsyncNotifierProvider<UpdateController, UpdateInfo?>(UpdateController.new);
