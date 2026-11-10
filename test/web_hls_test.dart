import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/licenses.dart';

/// The web player needs hls.js: browsers other than Safari (Chrome, Firefox, Edge) play no HLS
/// on their own, so a live channel would stay black. hls.js is bundled with the app (never loaded
/// from a third-party server) and declared in the licence list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('web HLS', () {
    test('bundles hls.js next to index.html', () {
      final file = File('web/hls.min.js');
      expect(file.existsSync(), isTrue, reason: 'web/hls.min.js must be shipped with the web build');
      expect(file.readAsStringSync(), contains('Hls'));
    });

    test('index.html loads the bundled hls.js before the app boots', () {
      final html = File('web/index.html').readAsStringSync();
      final hls = html.indexOf('hls.min.js');
      final boot = html.indexOf('flutter_bootstrap.js');
      expect(hls, isNonNegative, reason: 'index.html must load hls.min.js');
      expect(boot, isNonNegative);
      expect(hls, lessThan(boot), reason: 'hls.js must be ready before the app starts');
    });

    test('the hls.js licence is listed in "Licences"', () async {
      registerBundledLicenses();
      final packages = <String>[];
      await for (final license in LicenseRegistry.licenses) {
        packages.addAll(license.packages);
      }
      expect(packages, contains('hls.js'));
    });
  });
}
