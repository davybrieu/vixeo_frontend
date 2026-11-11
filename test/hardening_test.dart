import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vixeo/core/api/api_client.dart';
import 'package:vixeo/core/api/session_storage.dart';
import 'package:vixeo/core/config.dart';
import 'package:vixeo/features/auth/auth_repository.dart';
import 'package:vixeo/features/auth/models.dart';
import 'package:vixeo/features/auth/session.dart';

/// Keychain that refuses to read (e.g. a backup restored on another device).
class BrokenStorage extends MemorySessionStorage {
  bool cleared = false;

  @override
  Future<String?> readToken() async => throw Exception('keychain');

  @override
  Future<void> writeToken(String? value) async => cleared = value == null;
}

/// API answering something that is not the expected JSON.
class OddAuth extends AuthRepository {
  OddAuth() : super(ApiClient(token: () => null, profileId: () => null));

  @override
  Future<User> me() async => throw TypeError();
}

Future<SessionState> restoredWith(SessionStorage storage, AuthRepository auth) async {
  final container = ProviderContainer(
    overrides: [sessionStorageProvider.overrideWithValue(storage), authRepositoryProvider.overrideWithValue(auth)],
  );
  addTearDown(container.dispose);
  container.read(sessionProvider);
  await container.read(sessionProvider.notifier).restore();
  return container.read(sessionProvider);
}

void main() {
  group('API address check', () {
    String? check(String url, {bool given = true, bool release = true}) =>
        AppConfig.checkApiUrl(url, given: given, release: release);

    test('accepts https in release builds', () => expect(check('https://api.vixeo.app'), isNull));
    test('accepts plain http to this machine only (local tests)', () {
      expect(check('http://localhost:8000'), isNull);
      expect(check('http://10.0.2.2:8000'), isNull);
      expect(check('http://api.vixeo.app'), contains('https://'));
      expect(check('http://192.168.1.20:8000'), contains('https://'));
    });
    test('refuses a release build without API_URL', () {
      expect(check('http://localhost:8000', given: false), contains('--dart-define=API_URL'));
    });
    test('refuses an invalid address', () => expect(check('nimporte quoi'), contains('invalide')));
    test('lets debug builds use anything', () => expect(check('http://api.vixeo.app', release: false), isNull));
  });

  group('session restore never blocks the start screen', () {
    test('an unreadable keychain starts in guest mode', () async {
      final storage = BrokenStorage();
      final state = await restoredWith(storage, OddAuth());

      expect(state.status, SessionStatus.guest);
      expect(storage.cleared, isTrue);
    });

    test('a device without a saved token starts in guest mode', () async {
      final state = await restoredWith(MemorySessionStorage(), OddAuth());

      expect(state.status, SessionStatus.guest);
      expect(state.isGuest, isTrue);
      expect(state.isSignedIn, isFalse);
    });

    test('an unexpected API answer offers to try again', () async {
      final storage = MemorySessionStorage()..token = 'token-1';
      final state = await restoredWith(storage, OddAuth());

      expect(state.status, SessionStatus.unreachable);
      expect(state.message, contains('Réessayez'));
      expect(storage.token, 'token-1');
    });
  });
}
