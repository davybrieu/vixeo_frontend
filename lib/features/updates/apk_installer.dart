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
  /// Android's installer is open: the person confirms, then the new version starts.
  started,

  /// Vixeo may not install apps yet: Android's settings were opened, try again afterwards.
  permissionNeeded,

  /// The downloaded file doesn't match the expected SHA-256: deleted, nothing installed.
  corrupted,

  /// Download or installer failed (offline, server error…).
  failed,

  /// No APK for this release, or not on Android: open the install page instead.
  unavailable,
}

/// Android without a store: downloads the new APK (https only, no Vixeo token sent), checks its
/// SHA-256, then opens Android's installer (MainActivity, channel `app.vixeo/updates`). Android
/// itself refuses an APK signed with another key than the installed app.
class ApkInstaller {
  ApkInstaller({Dio? dio, MethodChannel? channel, Future<Directory> Function()? cacheDirectory, bool? onAndroid})
    : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))),
      _channel = channel ?? const MethodChannel('app.vixeo/updates'),
      _cacheDirectory = cacheDirectory ?? getTemporaryDirectory,
      _onAndroid = onAndroid ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final Dio _dio;
  final MethodChannel _channel;
  final Future<Directory> Function() _cacheDirectory;
  final bool _onAndroid;

  /// The app can install this release itself.
  bool canInstall(AppRelease? release) =>
      _onAndroid && release != null && _safeUrl(release.downloadUrl) && _validSha(release.sha256);

  Future<ApkInstallResult> install(AppRelease release, {void Function(double progress)? onProgress}) async {
    if (!canInstall(release)) return ApkInstallResult.unavailable;

    try {
      if (await _channel.invokeMethod<bool>('canInstall') != true) {
        await _channel.invokeMethod<bool>('openInstallSettings');
        return ApkInstallResult.permissionNeeded;
      }

      final folder = Directory('${(await _cacheDirectory()).path}/updates');
      if (await folder.exists()) await folder.delete(recursive: true); // older downloads
      await folder.create(recursive: true);
      final apk = File('${folder.path}/vixeo-${release.build}.apk');

      await _dio.download(
        release.downloadUrl!,
        apk.path,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );

      final digest = await sha256.bind(apk.openRead()).first;
      if (digest.toString() != release.sha256!.toLowerCase()) {
        await apk.delete();
        return ApkInstallResult.corrupted;
      }

      final opened = await _channel.invokeMethod<bool>('install', {'path': apk.path});
      return opened == true ? ApkInstallResult.started : ApkInstallResult.failed;
    } catch (_) {
      return ApkInstallResult.failed;
    }
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
