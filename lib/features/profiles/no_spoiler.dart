import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local preference: hide episode artwork and text until the episode is selected.
class NoSpoilerController extends AsyncNotifier<bool> {
  static const _key = 'no_spoiler';

  @override
  Future<bool> build() async {
    final value = await const FlutterSecureStorage().read(key: _key);
    return value == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncData(enabled);
    try {
      const storage = FlutterSecureStorage();
      if (enabled) {
        await storage.write(key: _key, value: 'true');
      } else {
        await storage.delete(key: _key);
      }
    } catch (_) {
      state = AsyncError(StateError('Impossible d’enregistrer le réglage No spoil.'), StackTrace.current);
      rethrow;
    }
  }
}

final noSpoilerProvider = AsyncNotifierProvider<NoSpoilerController, bool>(NoSpoilerController.new);
