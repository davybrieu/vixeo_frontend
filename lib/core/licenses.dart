import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences of what is bundled without being a package (fonts, crypto-js, the Lucide
/// popcorn icon) to the "Licences" page (`showLicensePage`), next to the packages' ones that
/// Flutter collects itself.
void registerBundledLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final family in const ['Sora', 'Inter']) {
      yield LicenseEntryWithLineBreaks([
        '$family (police)',
      ], await rootBundle.loadString('assets/fonts/OFL-$family.txt'));
    }
    // Lucide's popcorn icon: the logo of Rotten Tomatoes' audience score (assets/images/ratings).
    yield LicenseEntryWithLineBreaks(['Lucide'], await rootBundle.loadString('assets/licenses/lucide-ISC.txt'));
  });
}
