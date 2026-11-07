import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';

/// No-spoil preference belongs to the active profile and is synchronized by the API.
final noSpoilerProvider = Provider<bool>(
  (ref) => ref.watch(sessionProvider).profile?.noSpoiler ?? false,
);
