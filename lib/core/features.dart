/// Features hidden for a while, without removing their code.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live TV (« Chaînes TV ») is hidden for now (developer's request, 17/11/2026): no tab nor rail
/// entry, no channels in the search, in « Ma liste » or in the settings, and its pages lead to
/// the home page. Its code stays: build with `--dart-define=LIVE_TV=true` to show it again, or
/// change the default here.
const liveTvByDefault = bool.fromEnvironment('LIVE_TV');

/// Whether live TV is shown. A provider (like a Pinia getter) so that the tests can turn it on.
final liveTvProvider = Provider<bool>((ref) => liveTvByDefault);
