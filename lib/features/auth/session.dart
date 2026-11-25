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
  guest,
  /// Kept for explicit account-deletion flows and older tests; normal sign-out now enters guest mode.
  signedOut,
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

/// The real-time connection of the signed-in app (Reverb, `core/api/realtime.dart`): another
/// account or profile gets another one (other channels, another authorization).
final realtimeProvider = Provider<Realtime>((ref) {
  ref.watch(sessionProvider.select((s) => (s.token, s.profile?.id)));
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

/// Guest browsing or a signed-in account with its active profile.
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
      // Unreadable keychain entry (e.g. a backup restored on another device): clear it
      // and continue without an account.
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
      // The last profile chosen opens at launch.
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

  Future<void> register(String name, String username, String email, String password) async {
    final result = await _auth.register(name: name, username: username, email: email, password: password);
    await _signedIn(result.token, result.user);
  }

  Future<void> selectProfile(Profile profile) async {
    _previous = null;
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

  /// The profile left with « Changer de profil »: « Qui regarde ? » can go back to it.
  Profile? _previous;

  Profile? get previousProfile => _previous;

  /// Back to "Qui regarde ?".
  Future<void> switchProfile() async {
    _previous = state.profile;
    await _storage.writeProfileId(null);
    state = state.copyWith(clearProfile: true);
  }

  /// « Qui regarde ? »'s back button: the profile in use before, without asking its PIN again.
  Future<void> cancelSwitch() async {
    final previous = _previous;
    if (previous == null) return;
    _previous = null;
    await selectProfile(previous);
  }

  /// A profile deleted (« Modifier mon profil »): never back to it. The profile in
  /// use deleted: back to « Qui regarde ? ».
  Future<void> forgetProfile(int profileId) async {
    if (_previous?.id == profileId) _previous = null;
    if (state.profile?.id != profileId) return;
    await _storage.writeProfileId(null);
    state = state.copyWith(clearProfile: true);
  }

  /// Explicitly enter guest mode from the login screen.
  void continueAsGuest() {
    state = const SessionState(status: SessionStatus.guest);
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
    state = SessionState(status: SessionStatus.signedOut, message: message);
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
      // Nothing more to do if the keychain refuses: guest browsing remains available.
    }
  }
}
