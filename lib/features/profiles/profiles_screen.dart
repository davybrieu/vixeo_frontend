import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/models.dart';
import '../auth/session.dart';

/// The account's one profile, fetched after authentication.
final profilesProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.read(authRepositoryProvider).profiles();
});
