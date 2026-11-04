import '../../core/api/api_client.dart';
import '../../core/device/layout.dart';
import 'models.dart';

/// `/auth/*`, `/me` and `/profiles` endpoints.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<({String token, User user})> login({required String email, required String password}) async {
    final json = await _api.post(
      '/auth/login',
      body: {'email': email, 'password': password, 'device_name': DeviceInfo.deviceName},
    );
    return (token: json['token'] as String, user: User.fromJson(json['user'] as Map<String, dynamic>));
  }

  /// Creates the account and its first profile.
  Future<({String token, User user})> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final json = await _api.post(
      '/auth/register',
      body: {'name': name, 'email': email, 'password': password, 'device_name': DeviceInfo.deviceName},
    );
    return (token: json['token'] as String, user: User.fromJson(json['user'] as Map<String, dynamic>));
  }

  Future<User> me() async => User.fromJson((await _api.get('/me'))['data'] as Map<String, dynamic>);

  Future<void> logout() => _api.post('/auth/logout');

  Future<List<Profile>> profiles() async {
    final json = await _api.get('/profiles');
    return (json['data'] as List).cast<Map<String, dynamic>>().map(Profile.fromJson).toList();
  }

  Future<Profile> createProfile({required String name, bool isKid = false, String? parentalPin}) async {
    final json = await _api.post(
      '/profiles',
      body: {
        'name': name,
        'is_kid': isKid,
        if (parentalPin != null && parentalPin.isNotEmpty) 'parental_pin': parentalPin,
      },
    );
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Changes harmless profile fields (`name`, `avatar`, `poster_format`…).
  Future<Profile> updateProfile(int profileId, Map<String, Object?> fields) async {
    final json = await _api.patch('/profiles/$profileId', body: fields);
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Throws an [ApiException] with a `pin` field error when the PIN is wrong.
  Future<void> verifyProfilePin(int profileId, String pin) =>
      _api.post('/profiles/$profileId/verify-pin', body: {'pin': pin});
}
