import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/realtime.dart';
import '../../core/api/session_storage.dart';
import 'auth_repository.dart';
import 'models.dart';

enum SessionStatus {
  restoring,
  unreachable,
  signedOut,
  signedIn,
}

class SessionState {
  const SessionState({required this.status, this.token, this.user, this.profile, this.message});
  const SessionState.restoring() : this(status: SessionStatus.restoring);

  final SessionStatus status;
  final String? token;
  final User? user;
  final Profile? profile;
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

class SessionController extends Notifier<SessionState> {
  SessionStorage get _storage => ref.read(sessionStorageProvider);
  AuthRepository get _auth => ref.read(authRepositoryProvider);

  @override
  SessionState build() {
    Future.microtask(restore);
    return const SessionState.restoring();
  }

  Future<void> restore() async {
    state = const SessionState.restoring();
    String? token;
    try {
      token = await _storage.readToken();
    } catch (_) {
      await _clearQuietly();
      state = const SessionState(status: SessionStatus.signedOut);
      return;
    }
    if (token == null) {
      state = const SessionState(status: SessionStatus.signedOut);
      return;
    }

    state = SessionState(status: SessionStatus.restoring, token: token);
    try {
      final user = await _auth.me();
      // The profile is embedded in the account response; the old endpoint is a compatibility fallback.
      final legacyProfiles = user.profile == null ? await _auth.profiles() : const <Profile>[];
      final profile = user.profile ?? (legacyProfiles.isEmpty ? null : legacyProfiles.first);
      if (profile == null) {
        state = const SessionState(
          status: SessionStatus.unreachable,
          message: "Le compte ne contient pas encore de profil. Vérifiez la migration du compte côté serveur.",
        );
        return;
      }
      state = SessionState(status: SessionStatus.signedIn, token: token, user: user, profile: profile);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _clear();
        state = const SessionState(status: SessionStatus.signedOut);
      } else {
        state = SessionState(status: SessionStatus.unreachable, token: token, message: e.message);
      }
    } catch (_) {
      state = const SessionState(
        status: SessionStatus.unreachable,
        message: 'Le serveur a envoyé une réponse inattendue. Réessayez dans un instant.',
      );
    }
  }

  Future<void> signInWithToken(String token, User user) => _signedIn(token, user);

  Future<void> refreshUser() async {
    if (!state.isSignedIn) return;
    final user = await _auth.me();
    state = state.copyWith(user: user, profile: user.profile);
  }

  void updateUser(User user) {
    if (state.isSignedIn) state = state.copyWith(user: user, profile: user.profile);
  }

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

  Future<void> expire() async {
    if (!state.isSignedIn) return;
    await _clear();
    state = const SessionState(status: SessionStatus.signedOut, message: 'Votre session a expiré. Reconnectez-vous.');
  }

  Future<void> forget({String? message}) async {
    await _clearQuietly();
    state = SessionState(status: SessionStatus.signedOut, message: message);
  }

  Future<void> _signedIn(String token, User user) async {
    await _storage.writeToken(token);
    Profile? profile = user.profile;
    if (profile == null) {
      try {
        final profiles = await _auth.profiles();
        profile = profiles.isEmpty ? null : profiles.first;
      } catch (_) {
        // Session restoration will retry with the account resource.
      }
    }
    if (profile == null) {
      state = SessionState(
        status: SessionStatus.unreachable,
        token: token,
        user: user,
        message: "Le profil du compte n'a pas pu être chargé. Réessayez après la mise à jour du serveur.",
      );
      return;
    }
    state = SessionState(status: SessionStatus.signedIn, token: token, user: user, profile: profile);
  }

  Future<void> _clear() async {
    await _storage.writeToken(null);
  }

  Future<void> _clearQuietly() async {
    try {
      await _clear();
    } catch (_) {}
  }
}
