import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'updates.dart';

/// What happened when installing an update.
enum ApkInstallResult {
  /// Android's installer is open (the person confirms, then the new version starts), or Windows'
  /// installer runs and Vixeo closes, to restart once installed.
  started,

  /// Vixeo may not install apps yet: Android's settings were opened, try again afterwards.
  permissionNeeded,

  /// The downloaded file doesn't match the expected SHA-256: deleted, nothing installed.
  corrupted,

  /// Download or installer failed (offline, server error…).
  failed,

  /// No file for this release, or not on Android / Windows: open the install page instead.
  unavailable,
}

/// Updates without a store (vixeo_backend/docs/mise-a-jour.md): downloads the new version's file
/// (https only, no Vixeo token sent) and checks its SHA-256, then
/// - Android: opens Android's installer for the APK (MainActivity, channel `app.vixeo/updates`).
///   Android itself refuses an APK signed with another key than the installed app;
/// - Windows: runs the installer (`/SILENT`: a progress window, no question) and closes Vixeo,
///   which the installer starts again once done.
class ApkInstaller {
  ApkInstaller({
    Dio? dio,
    MethodChannel? channel,
    Future<Directory> Function()? cacheDirectory,
    bool? onAndroid,
    bool? onWindows,
    Future<void> Function(String installer)? runInstaller,
  }) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))),
       _channel = channel ?? const MethodChannel('app.vixeo/updates'),
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory,
       _onAndroid = onAndroid ?? defaultTargetPlatform == TargetPlatform.android,
       _onWindows = onWindows ?? Platform.isWindows,
       _runInstaller = runInstaller ?? _runAndQuit;

  final Dio _dio;
  final MethodChannel _channel;
  final Future<Directory> Function() _cacheDirectory;
  final bool _onAndroid;
  final bool _onWindows;
  final Future<void> Function(String installer) _runInstaller;

  /// The app can install this release itself.
  bool canInstall(AppRelease? release) =>
      (_onAndroid || _onWindows) && release != null && _safeUrl(release.downloadUrl) && _validSha(release.sha256);

  Future<ApkInstallResult> install(AppRelease release, {void Function(double progress)? onProgress}) async {
    if (!canInstall(release)) return ApkInstallResult.unavailable;
    if (_onWindows) return _installOnWindows(release, onProgress);

    try {
      if (await _channel.invokeMethod<bool>('canInstall') != true) {
        await _channel.invokeMethod<bool>('openInstallSettings');
        return ApkInstallResult.permissionNeeded;
      }

      final apk = await _download(release, 'vixeo-${release.build}.apk', onProgress);
      if (apk == null) return ApkInstallResult.corrupted;

      final opened = await _channel.invokeMethod<bool>('install', {'path': apk.path});
      return opened == true ? ApkInstallResult.started : ApkInstallResult.failed;
    } catch (_) {
      return ApkInstallResult.failed;
    }
  }

  /// Windows: the installer of the new version, run once its SHA-256 is right.
  Future<ApkInstallResult> _installOnWindows(AppRelease release, void Function(double progress)? onProgress) async {
    try {
      final installer = await _download(release, 'vixeo-setup-${release.build}.exe', onProgress);
      if (installer == null) return ApkInstallResult.corrupted;
      await _runInstaller(installer.path);
      return ApkInstallResult.started;
    } catch (_) {
      return ApkInstallResult.failed;
    }
  }

  /// Downloads [release]'s file into a fresh `updates` folder; null (and nothing kept) when its
  /// SHA-256 is not the expected one.
  Future<File?> _download(AppRelease release, String name, void Function(double progress)? onProgress) async {
    final folder = Directory('${(await _cacheDirectory()).path}/updates');
    if (await folder.exists()) await folder.delete(recursive: true); // older downloads
    await folder.create(recursive: true);
    final file = File('${folder.path}/$name');
    await _dio.download(
      release.downloadUrl!,
      file.path,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != release.sha256!.toLowerCase()) {
      await file.delete();
      return null;
    }
    return file;
  }

  /// Starts the Inno Setup installer on its own (it outlives Vixeo), then closes Vixeo so that its
  /// files can be replaced. The installer starts Vixeo again at the end (`windows/installer.iss`).
  static Future<void> _runAndQuit(String installer) async {
    await Process.start(installer, const [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
    ], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(seconds: 1));
    exit(0);
  }

  static bool _validSha(String? value) => value != null && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  /// https only; plain http to this machine in debug builds (local tests).
  static bool _safeUrl(String? url) {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null || uri.host.isEmpty) return false;
    return uri.scheme == 'https' || (!kReleaseMode && uri.scheme == 'http');
  }
}

final apkInstallerProvider = Provider<ApkInstaller>((ref) => ApkInstaller());

/// Download and installation of the new APK, shared by the update banner and the blocking
/// "Mise à jour nécessaire" screen: both show the same progress.
class UpdateDownload {
  const UpdateDownload({this.busy = false, this.progress, this.result});

  final bool busy;

  /// 0 to 1 once the size of the file is known.
  final double? progress;

  /// Outcome of the last attempt (null before the first one).
  final ApkInstallResult? result;

  /// The last attempt didn't open Android's installer: the button becomes "Réessayer".
  bool get failed => result != null && result != ApkInstallResult.started;
}

class UpdateDownloadController extends Notifier<UpdateDownload> {
  @override
  UpdateDownload build() => const UpdateDownload();

  Future<void> install(AppRelease release) async {
    if (state.busy) return;
    state = const UpdateDownload(busy: true);
    final result = await ref
        .read(apkInstallerProvider)
        .install(
          release,
          onProgress: (value) {
            // Whole percents: no rebuild for every received chunk.
            final previous = state.progress;
            if (ref.mounted && (previous == null || (value * 100).round() != (previous * 100).round())) {
              state = UpdateDownload(busy: true, progress: value);
            }
          },
        );
    if (ref.mounted) state = UpdateDownload(result: result);
  }
}

final updateDownloadProvider = NotifierProvider<UpdateDownloadController, UpdateDownload>(UpdateDownloadController.new);
