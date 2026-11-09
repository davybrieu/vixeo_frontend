import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/auth/session.dart';
import 'package:vixeo/features/updates/apk_installer.dart';
import 'package:vixeo/features/updates/update_gate.dart';
import 'package:vixeo/features/updates/updates.dart';

/// Answers with [next], and records the builds it was asked about.
class FakeUpdates extends UpdateRepository {
  FakeUpdates(this.next) : super(ApiClient(token: () => null, profileId: () => null));

  UpdateInfo Function() next;
  final asked = <String>[];

  @override
  Future<UpdateInfo> check(UpdatePlatform platform, InstalledVersion installed) async {
    asked.add('${platform.name} ${installed.build}');
    return next();
  }
}

UpdateInfo info(UpdateStatus status, {String version = '1.2.0', int build = 14, String? notes}) => UpdateInfo(
  status: status,
  latest: AppRelease(version: version, build: build, notes: notes),
  updateUrl: 'https://play.google.com/store/apps/details?id=app.vixeo.vixeo',
);

/// The saved session is restored: the gate may show its dialog (not over the start screen).
class Restored extends SessionController {
  @override
  SessionState build() => const SessionState(status: SessionStatus.signedOut);
}

Future<FakeUpdates> pumpApp(
  WidgetTester tester,
  UpdateInfo Function() next, {
  UpdatePlatform? platform = UpdatePlatform.android,
}) async {
  final updates = FakeUpdates(next);
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        updatePlatformProvider.overrideWithValue(platform),
        installedVersionProvider.overrideWith((ref) async => const InstalledVersion(version: '1.0.0', build: 3)),
        updateRepositoryProvider.overrideWithValue(updates),
        sessionProvider.overrideWith(Restored.new),
      ],
      child: MaterialApp(
        theme: buildVixeoTheme(),
        navigatorKey: key,
        builder: (context, child) => UpdateGate(navigatorKey: key, child: child!),
        home: const Scaffold(body: Text('Accueil')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return updates;
}

void main() {
  test('reads the API answer', () {
    final parsed = UpdateInfo.fromJson({
      'status': 'update_required',
      'current_build': 3,
      'latest': {'version': '1.2.0', 'build': 14, 'notes': '  ', 'published_at': '2026-11-06T08:00:00+00:00'},
      'minimum_build': 10,
      'update_url': 'https://vixeo.app/telecharger',
    });
    expect(parsed.status, UpdateStatus.updateRequired);
    expect(parsed.latest!.version, '1.2.0');
    expect(parsed.latest!.notes, isNull);
    expect(parsed.updateUrl, 'https://vixeo.app/telecharger');

    expect(UpdateInfo.fromJson({'status': 'up_to_date', 'latest': null}).latest, isNull);
    expect(UpdateInfo.fromJson({'status': 'something_new'}).status, UpdateStatus.upToDate);
  });

  testWidgets('blocks the app while the installed version is no longer accepted', (tester) async {
    var answer = info(UpdateStatus.updateRequired, notes: 'Correctif de sécurité.');
    final updates = await pumpApp(tester, () => answer);

    expect(updates.asked, ['android 3']);
    expect(find.text('Mise à jour nécessaire'), findsOneWidget);
    expect(find.textContaining('Installez la version 1.2.0'), findsOneWidget);
    expect(find.text('Correctif de sécurité.'), findsOneWidget);
    expect(find.text('Accueil'), findsNothing);

    // Updated (or the release is no longer required): "Réessayer" lets the app in.
    answer = info(UpdateStatus.upToDate);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Accueil'), findsOneWidget);
  });

  testWidgets('suggests a newer version once', (tester) async {
    final updates = await pumpApp(tester, () => info(UpdateStatus.updateAvailable, notes: 'Page acteur.'));

    expect(find.text('Accueil'), findsOneWidget);
    // A generic message: GitHub release notes are lists of commits, not meant for viewers.
    expect(find.text('Une mise à jour est disponible'), findsOneWidget);
    expect(find.textContaining('garder Vixeo à jour'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // Same release again (back to the foreground…): not suggested twice.
    final container = ProviderScope.containerOf(tester.element(find.text('Accueil')));
    await container.read(updateProvider.notifier).check();
    await tester.pumpAndSettle();
    expect(updates.asked, hasLength(2));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('never blocks when the check fails (offline…)', (tester) async {
    await pumpApp(tester, () => throw const ApiException('Impossible de joindre le serveur.'));

    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Mise à jour nécessaire'), findsNothing);
  });

  testWidgets('does not check on the web', (tester) async {
    final updates = await pumpApp(tester, () => info(UpdateStatus.updateRequired), platform: null);

    expect(updates.asked, isEmpty);
    expect(find.text('Accueil'), findsOneWidget);
  });

  testWidgets('checks again when the app comes back after a while', (tester) async {
    final updates = await pumpApp(tester, () => info(UpdateStatus.upToDate));
    final container = ProviderScope.containerOf(tester.element(find.text('Accueil')));

    await container.read(updateProvider.notifier).checkIfStale();
    expect(updates.asked, hasLength(1), reason: 'just checked');
  });

  group('APK installer', () {
    final apk = utf8.encode('fake apk bytes');
    final goodSha = sha256.convert(apk).toString();
    late Directory cache;
    late FakeInstallerChannel native;
    const channel = MethodChannel('app.vixeo/updates.test');

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('vixeo-updates');
      native = FakeInstallerChannel();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        native.handle,
      );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await cache.delete(recursive: true);
    });

    ApkInstaller installer(BytesAdapter adapter, {bool onAndroid = true}) => ApkInstaller(
      dio: Dio()..httpClientAdapter = adapter,
      channel: channel,
      cacheDirectory: () async => cache,
      onAndroid: onAndroid,
    );

    AppRelease release({String? sha, String url = 'https://vixeo.test/vixeo-1.2.0.apk'}) =>
        AppRelease(version: '1.2.0', build: 14, downloadUrl: url, sha256: sha ?? goodSha);

    test('reads the APK fields of the API', () {
      final parsed = AppRelease.fromJson({
        'version': '1.2.0',
        'build': 14,
        'download_url': 'https://vixeo.test/vixeo.apk',
        'sha256': goodSha,
      });
      expect(parsed.downloadUrl, 'https://vixeo.test/vixeo.apk');
      expect(parsed.sha256, goodSha);
    });

    test('downloads, checks the SHA-256 and opens Android installer', () async {
      final adapter = BytesAdapter(apk);
      final progress = <double>[];

      final result = await installer(adapter).install(release(), onProgress: progress.add);

      expect(result, ApkInstallResult.started);
      expect(progress.last, 1.0);
      expect(native.calls, ['canInstall', 'install ${cache.path}/updates/vixeo-14.apk']);
      expect(File('${cache.path}/updates/vixeo-14.apk').readAsBytesSync(), apk);
      // The APK host never receives the Vixeo token.
      expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('refuses a file whose SHA-256 does not match', () async {
      final result = await installer(BytesAdapter(apk)).install(release(sha: 'a' * 64));

      expect(result, ApkInstallResult.corrupted);
      expect(native.calls, ['canInstall']);
      expect(File('${cache.path}/updates/vixeo-14.apk').existsSync(), isFalse);
    });

    test('asks for the "install unknown apps" permission first', () async {
      native.canInstall = false;
      final adapter = BytesAdapter(apk);

      final result = await installer(adapter).install(release());

      expect(result, ApkInstallResult.permissionNeeded);
      expect(native.calls, ['canInstall', 'openInstallSettings']);
      expect(adapter.requests, isEmpty);
    });

    test('only installs an https APK with a checksum, on Android', () {
      final adapter = BytesAdapter(apk);
      expect(installer(adapter).canInstall(release(url: 'ftp://vixeo.test/a.apk')), isFalse);
      expect(installer(adapter).canInstall(const AppRelease(version: '1.2.0', build: 14)), isFalse);
      expect(installer(adapter).canInstall(release(sha: 'nope')), isFalse);
      expect(installer(adapter, onAndroid: false).canInstall(release()), isFalse);
      expect(installer(adapter).canInstall(release()), isTrue);
    });
  });

  testWidgets('"Mettre à jour" shows the download, then asks to confirm the installation', (tester) async {
    final installer = FakeApkInstaller(ApkInstallResult.started);
    const info = UpdateInfo(
      status: UpdateStatus.updateAvailable,
      latest: AppRelease(version: '1.2.0', build: 14, downloadUrl: 'https://vixeo.test/a.apk', sha256: 'x'),
      updateUrl: 'https://vixeo.test/installer',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apkInstallerProvider.overrideWithValue(installer)],
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: const Scaffold(body: UpdateButton(info: info)),
        ),
      ),
    );
    await tester.tap(find.text('Mettre à jour'));
    await tester.pump();
    expect(find.text('Téléchargement… 40 %'), findsOneWidget);

    installer.finish();
    await tester.pumpAndSettle();
    expect(find.textContaining('Confirmez l’installation'), findsOneWidget);
    expect(installer.installed, ['1.2.0']);
  });

  testWidgets('"Mettre à jour" explains the Android permission and offers to try again', (tester) async {
    final installer = FakeApkInstaller(ApkInstallResult.permissionNeeded)..finish();
    const info = UpdateInfo(
      status: UpdateStatus.updateRequired,
      latest: AppRelease(version: '1.2.0', build: 14, downloadUrl: 'https://vixeo.test/a.apk', sha256: 'x'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apkInstallerProvider.overrideWithValue(installer)],
        child: MaterialApp(
          theme: buildVixeoTheme(),
          home: const Scaffold(body: UpdateButton(info: info)),
        ),
      ),
    );
    await tester.tap(find.text('Mettre à jour'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Installer des applis inconnues'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}

// ── APK updates (no Play Store) ──

class FakeInstallerChannel {
  FakeInstallerChannel({this.canInstall = true});

  bool canInstall;
  final calls = <String>[];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method == 'install' ? 'install ${(call.arguments as Map)['path']}' : call.method);
    return switch (call.method) {
      'canInstall' => canInstall,
      _ => true,
    };
  }
}

/// Installer whose result is decided by the test (the real one is tested above).
class FakeApkInstaller extends ApkInstaller {
  FakeApkInstaller(this.result) : super(onAndroid: true);

  final ApkInstallResult result;
  final installed = <String>[];
  final _done = Completer<void>();

  void finish() => _done.complete();

  @override
  bool canInstall(AppRelease? release) => release?.downloadUrl != null;

  @override
  Future<ApkInstallResult> install(AppRelease release, {void Function(double progress)? onProgress}) async {
    onProgress?.call(0.4);
    await _done.future;
    installed.add(release.version);
    return result;
  }
}

/// Serves [bytes] as the APK, without network.
class BytesAdapter implements HttpClientAdapter {
  BytesAdapter(this.bytes);

  final List<int> bytes;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(options);
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
