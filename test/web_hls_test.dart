import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/licenses.dart';

/// The web player needs hls.js: browsers other than Safari (Chrome, Firefox, Edge) play no HLS
/// on their own, so a live channel would stay black. hls.js is bundled with the app (never loaded
/// from a third-party server), declared in the licence list, and only downloaded by the browsers
/// that need it (the player adds its script on demand).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('web HLS', () {
    test('bundles hls.js next to index.html', () {
      final file = File('web/hls.min.js');
      expect(file.existsSync(), isTrue, reason: 'web/hls.min.js must be shipped with the web build');
      expect(file.readAsStringSync(), contains('Hls'));
    });

    test('index.html does not load hls.js: the player does, only when a stream needs it', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, isNot(contains('<script src="hls.min.js"')), reason: 'Safari plays HLS on its own');
      expect(html, contains('flutter_bootstrap.js'));

      final loader = File('lib/features/playback/engine/web/hls_js_interop.dart').readAsStringSync();
      expect(loader, contains("'hls.min.js'"), reason: 'the bundled copy, on our own origin');
      expect(loader, isNot(contains('https://')), reason: 'never from a third-party server');
    });

    test('the web build never imports the native player plugin', () {
      // better_native_video_player has no web implementation: only the io side of the
      // conditional import may reach it.
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        if (source.contains("import 'package:better_native_video_player/")) {
          expect(file.path, endsWith('native_player_engine.dart'));
        }
        if (source.contains("import 'native_player_engine.dart'")) {
          expect(file.path, endsWith('engine_factory_io.dart'));
        }
      }
      final factory = File('lib/features/playback/engine/engine_factory.dart').readAsStringSync();
      expect(factory, contains("import 'engine_factory_io.dart' if (dart.library.js_interop) 'engine_factory_web.dart'"));
      final web = File('lib/features/playback/engine/engine_factory_web.dart').readAsStringSync();
      expect(web, isNot(contains('native_player_engine')));
      expect(web, isNot(contains('dart:io')));
    });

    test('no HTML loading screen before the app: only the app (Flutter) shows a loading', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, isNot(contains('boot-loader')));
      expect(html, isNot(contains('flutter-first-frame')));
      // The page stays dark until Flutter draws (no white flash).
      expect(html, contains('background: #070A08'));
    });

    test('the hls.js licence is listed in "Licences"', () async {
      registerBundledLicenses();
      final packages = <String>[];
      await for (final license in LicenseRegistry.licenses) {
        packages.addAll(license.packages);
      }
      expect(packages, contains('hls.js'));
      // And crypto-js, lent to the plug-in scrapers (assets/scrapers).
      expect(packages, contains('crypto-js'));
    });
  });
}
