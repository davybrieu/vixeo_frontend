import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/api_exception.dart';
import 'package:vixeo/core/theme.dart';
import 'package:vixeo/features/updates/update_gate.dart';
import 'package:vixeo/features/updates/updates.dart';

/// Answers with [next], and records the builds it was asked about.
class FakeUpdates extends UpdateRepository {
  FakeUpdates(this.next) : super(ApiClient(token: () => null, profileId: () => null));

  UpdateInfo Function() next;
  final asked = <String>[];

  @override
  Future<UpdateInfo> check(UpdatePlatform platform, int build) async {
    asked.add('${platform.name} $build');
    return next();
  }
}

UpdateInfo info(UpdateStatus status, {String version = '1.2.0', int build = 14, String? notes}) => UpdateInfo(
  status: status,
  latest: AppRelease(version: version, build: build, notes: notes),
  updateUrl: 'https://play.google.com/store/apps/details?id=app.vixeo.vixeo',
);

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
    expect(find.text('Vixeo 1.2.0 est disponible'), findsOneWidget);
    expect(find.text('Page acteur.'), findsOneWidget);
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
}
