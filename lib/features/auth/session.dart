import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/realtime.dart';
import '../../core/api/session_storage.dart';
import 'auth_repository.dart';
import 'models.dart';

enum SessionStatus {
  /// Reading the saved session at startup.
  restoring,

  /// The saved session could not be checked (API unreachable).
  unreachable,
  /// No valid account session is available on this device.
  signedOut,
  signedIn,
}

class SessionState {
  const SessionState({required this.status, this.token, this.user, this.profile, this.message});

  const SessionState.restoring() : this(status: SessionStatus.restoring);

  final SessionStatus status;
  final String? token;
  final User? user;

  /// The account's single profile, resolved automatically after sign-in.
  final Profile? profile;

  /// Message to show once (e.g. "session expirée").
  final String? message;

  bool get isSignedIn => status == SessionStatus.signedIn;

  SessionState copyWith({User? user, Profile? profile}) => SessionState(
    status: status,
    token: token,
    user: user ?? this.user,
    profile: profile ?? this.profile,
  );
}

final sessionStorageProvider = Provider<SessionStorage>((ref) => SecureSessionStorage());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    token: () => ref.read(sessionProvider).token,
    onUnauthorized: () => ref.read(sessionProvider.notifier).expire(),
  ),
);

/// The real-time connection of the signed-in account (Reverb).
final realtimeProvider = Provider<Realtime>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  final api = ref.read(apiClientProvider);
  final realtime = Realtime(
    authorize: (socketId, channel) async =>
        (await api.authorizeBroadcasting(socketId: socketId, channelName: channel))['auth'] as String?,
  );
  ref.onDispose(realtime.dispose);
  return realtime;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.read(apiClientProvider)));

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Authentication state and the single profile of the signed-in account.
class SessionController extends Notifier<SessionState> {
  SessionStorage get _storage => ref.read(sessionStorageProvider);
  AuthRepository get _auth => ref.read(authRepositoryProvider);

  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionState.restoring();
  }

  /// Reads the saved token and checks it with `GET /me`.
  Future<void> restore() async {
    state = const SessionState.restoring();
    String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      // An unreadable keychain entry cannot be used to authenticate.
      await _clearQuietly();
      state = const SessionState(status: SessionStatus.signedOut);
      return;
    }
    if (token == null) {
      state = const SessionState(status: SessionStatus.signedOut);
      return;
    }

    // Token needed by the API client for the checks below.
    state = SessionState(status: SessionStatus.restoring, token: token);
    try {
      final user = await _auth.me();
      // One account has one viewer identity: use its sole profile automatically.
      final profiles = await _auth.profiles();
      final profile = profiles.isEmpty ? null : profiles.first;
      state = SessionState(status: SessionStatus.signedIn, token: token, user: user, profile: profile);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _clear();
        state = const SessionState(status: SessionStatus.signedOut);
      } else {
        state = SessionState(status: SessionStatus.unreachable, message: e.message);
      }
    } catch (_) {
      // Unexpected answer (not the JSON the app expects): the start screen offers "Réessayer".
      state = const SessionState(
        status: SessionStatus.unreachable,
        message: 'Le serveur a envoyé une réponse inattendue. Réessayez dans un instant.',
      );
    }
  }

  Future<void> login(String email, String password) async {
    final result = await _auth.login(email: email, password: password);
    await _signedIn(result.token, result.user);
  }

  Future<void> register(String name, String username, String email, String password) async {
    final result = await _auth.register(name: name, username: username, email: email, password: password);
    await _signedIn(result.token, result.user);
  }

  /// Signed in by another device (TV approved from a phone).
  Future<void> signInWithToken(String token, User user) => _signedIn(token, user);

  /// Re-reads the account.
  Future<void> refreshUser() async {
    if (!state.isSignedIn) return;
    state = state.copyWith(user: await _auth.me());
  }

  /// The account was edited (new e-mail address…).
  void updateUser(User user) {
    if (state.isSignedIn) state = state.copyWith(user: user);
  }

  /// The active profile was edited (avatar, poster format…).
  void updateProfile(Profile profile) {
    if (state.profile?.id == profile.id) {
      state = state.copyWith(profile: profile);
    }
  }

  Future<void> logout() async {
    try {
      await _auth.logout();
    } on ApiException {
      // Signing out locally is enough if the API cannot be reached.
    }
    await _clear();
    state = const SessionState(status: SessionStatus.signedOut);
  }

  /// The API answered 401: the token was revoked or expired.
  Future<void> expire() async {
    if (!state.isSignedIn) return;
    await _clear();
    state = const SessionState(status: SessionStatus.signedOut, message: 'Votre session a expiré. Reconnectez-vous.');
  }

  /// The account was deleted, or its token revoked on purpose: forget it on this device.
  Future<void> forget({String? message}) async {
    await _clearQuietly();
    state = SessionState(status: SessionStatus.signedOut, message: message);
  }

  Future<void> _signedIn(String token, User user) async {
    await _storage.writeToken(token);
    // Do not persist a selected profile. Resolve the account's single profile on every sign-in.
    Profile? profile;
    try {
      final profiles = await _auth.profiles();
      profile = profiles.isEmpty ? null : profiles.first;
    } catch (_) {
      // Keep the authenticated session; the profile can be resolved on the next restore.
    }
    state = SessionState(status: SessionStatus.signedIn, token: token, user: user, profile: profile);
  }

  Future<void> _clear() async {
    await _storage.writeToken(null);
  }

  Future<void> _clearQuietly() async {
    try {
      await _clear();
    } catch (_) {
      // Nothing more to do if the keychain refuses.
    }
  }
}
