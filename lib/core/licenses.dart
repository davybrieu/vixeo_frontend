import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of what is bundled without being a package (fonts, hls.js, crypto-js) to the
/// "Licences" page (`showLicensePage`), next to the packages' ones that Flutter collects itself.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final family in const ['Sora', 'Inter']) {
      yield LicenseEntryWithLineBreaks([
        '$family (police)',
      ], await rootBundle.loadString('assets/fonts/OFL-$family.txt'));
    }
    // hls.js, bundled in web/hls.min.js to play HLS in browsers without native support.
    yield LicenseEntryWithLineBreaks(['hls.js'], await rootBundle.loadString('assets/licenses/hls-js-Apache-2.0.txt'));
    // crypto-js, bundled in assets/scrapers and lent to the plug-in scrapers that use it.
    yield LicenseEntryWithLineBreaks(['crypto-js'], await rootBundle.loadString('assets/licenses/crypto-js-MIT.txt'));
  });
}
