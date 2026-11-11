import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/session_storage.dart';
import 'auth_repository.dart';
import 'models.dart';

enum SessionStatus {
  /// Reading the saved session at startup.
  restoring,

  /// The saved session could not be checked (API unreachable).
  unreachable,
  guest,
  signedIn,
}

class SessionState {
  const SessionState({required this.status, this.token, this.user, this.profile, this.message});

  const SessionState.restoring() : this(status: SessionStatus.restoring);

  final SessionStatus status;
  final String? token;
  final User? user;

  /// Profile chosen on "Qui regarde ?" (null = not chosen yet).
  final Profile? profile;

  /// Message to show once (e.g. "session expirée").
  final String? message;

  bool get isSignedIn => status == SessionStatus.signedIn;
  bool get isGuest => status == SessionStatus.guest;

  SessionState copyWith({User? user, Profile? profile, bool clearProfile = false}) => SessionState(
    status: status,
    token: token,
    user: user ?? this.user,
    profile: clearProfile ? null : (profile ?? this.profile),
  );
}

final sessionStorageProvider = Provider<SessionStorage>((ref) => SecureSessionStorage());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    token: () => ref.read(sessionProvider).token,
    profileId: () => ref.read(sessionProvider).profile?.id,
    onUnauthorized: () => ref.read(sessionProvider.notifier).expire(),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.read(apiClientProvider)));

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Signed-in account and active profile.
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
      // Unreadable keychain entry (e.g. a backup restored on another device): sign in again
      // rather than staying on the start screen.
      await _clearQuietly();
      state = const SessionState(status: SessionStatus.guest);
      return;
    }
    if (token == null) {
      state = const SessionState(status: SessionStatus.guest);
      return;
    }

    // Token needed by the API client for the checks below.
    state = SessionState(status: SessionStatus.restoring, token: token);
    try {
      final user = await _auth.me();
      final profileId = await _storage.readProfileId();
      Profile? profile;
      if (profileId != null) {
        final profiles = await _auth.profiles();
        // A protected profile always asks for its PIN again after a restart.
        profile = profiles.where((p) => p.id == profileId && !p.hasPin).firstOrNull;
      }
      state = SessionState(status: SessionStatus.signedIn, token: token, user: user, profile: profile);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _clear();
        state = const SessionState(status: SessionStatus.guest);
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

  Future<void> register(String name, String email, String password) async {
    final result = await _auth.register(name: name, email: email, password: password);
    await _signedIn(result.token, result.user);
  }

  Future<void> selectProfile(Profile profile) async {
    await _storage.writeProfileId(profile.id);
    state = state.copyWith(profile: profile);
  }

  /// Signed in by another device (TV approved from a phone).
  Future<void> signInWithToken(String token, User user) => _signedIn(token, user);

  /// Re-reads the account (e.g. after turning parental control on or off).
  Future<void> refreshUser() async {
    if (!state.isSignedIn) return;
    state = state.copyWith(user: await _auth.me());
  }

  /// The active profile was edited (avatar, poster format…).
  void updateProfile(Profile profile) {
    if (state.profile?.id == profile.id) {
      state = state.copyWith(profile: profile);
    }
  }

  /// Back to "Qui regarde ?".
  Future<void> switchProfile() async {
    await _storage.writeProfileId(null);
    state = state.copyWith(clearProfile: true);
  }

  Future<void> logout() async {
    try {
      await _auth.logout();
    } on ApiException {
      // Signing out locally is enough if the API cannot be reached.
    }
    await _clear();
    state = const SessionState(status: SessionStatus.guest);
  }

  /// The API answered 401: the token was revoked or expired.
  Future<void> expire() async {
    if (!state.isSignedIn) return;
    await _clear();
    state = const SessionState(status: SessionStatus.guest, message: 'Votre session a expiré. Reconnectez-vous.');
  }

  /// The account was deleted, or its token revoked on purpose: forget it on this device.
  Future<void> forget({String? message}) async {
    await _clearQuietly();
    state = SessionState(status: SessionStatus.guest, message: message);
  }

  Future<void> _signedIn(String token, User user) async {
    await _storage.writeToken(token);
    await _storage.writeProfileId(null);
    state = SessionState(status: SessionStatus.signedIn, token: token, user: user);
  }

  Future<void> _clear() async {
    await _storage.writeToken(null);
    await _storage.writeProfileId(null);
  }

  Future<void> _clearQuietly() async {
    try {
      await _clear();
    } catch (_) {
      // Nothing more to do if the keychain refuses: the user signs in again.
    }
  }
}
