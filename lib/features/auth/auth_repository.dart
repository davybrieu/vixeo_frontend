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

  // ── Forgotten password (vixeo_backend/docs/compte.md) ──

  /// E-mails a 6-digit code if an account uses this address. Returns the API's message.
  Future<String> forgotPassword(String email) async =>
      (await _api.post('/auth/password/forgot', body: {'email': email}))['message'] as String? ?? '';

  /// New password with the code; signs out the other devices and signs this one in.
  Future<({String token, User user})> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    final json = await _api.post(
      '/auth/password/reset',
      body: {'email': email, 'code': code, 'password': password, 'device_name': DeviceInfo.deviceName},
    );
    return (token: json['token'] as String, user: User.fromJson(json['user'] as Map<String, dynamic>));
  }

  // ── Account: devices, data, deletion ──

  Future<List<Device>> devices() async {
    final json = await _api.get('/me/devices');
    return (json['data'] as List).cast<Map<String, dynamic>>().map(Device.fromJson).toList();
  }

  Future<void> revokeDevice(int id) => _api.delete('/me/devices/$id');

  /// E-mails the account's data (JSON). Returns the API's message.
  Future<String> exportData() async => (await _api.post('/me/export'))['message'] as String? ?? '';

  /// Deletes the account and all its data. Throws an [ApiException] (`password`) when wrong.
  Future<void> deleteAccount(String password) => _api.post('/me/delete', body: {'password': password});

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

  // ── TV sign-in with a QR code (vixeo_backend/docs/connexion-tv.md) ──

  /// The TV asks for a code to show.
  Future<DeviceCode> startDeviceLogin() async =>
      DeviceCode.fromJson(await _api.post('/auth/device', body: {'device_name': DeviceInfo.deviceName}));

  /// The TV polls: null while pending, the session once approved.
  /// Throws an [ApiException] with status 410 when the code expired: ask a new one.
  Future<({String token, User user})?> pollDeviceLogin(String deviceCode) async {
    final json = await _api.post('/auth/device/token', body: {'device_code': deviceCode});
    if (json['status'] != 'approved') return null;
    return (token: json['token'] as String, user: User.fromJson(json['user'] as Map<String, dynamic>));
  }

  /// Signed-in phone: which device asks for this code?
  Future<String> lookupDeviceLogin(String userCode) async =>
      (await _api.post('/auth/device/lookup', body: {'user_code': userCode}))['device_name'] as String? ?? '';

  /// Signed-in phone: sign the TV in to this account.
  Future<void> approveDeviceLogin(String userCode) => _api.post('/auth/device/approve', body: {'user_code': userCode});

  // ── Parental control (vixeo_backend/docs/controle-parental.md) ──

  Future<bool> parentalControlEnabled() async => (await _api.get('/parental-control'))['enabled'] as bool? ?? false;

  /// Sets (or changes, with [currentPin] or [password]) the parental PIN.
  Future<void> setParentalPin(String pin, {String? currentPin, String? password}) =>
      _api.put('/parental-control/pin', body: {'pin': pin, 'current_pin': ?currentPin, 'password': ?password});

  /// Turns parental control off, with the current PIN or the account password.
  Future<void> disableParentalControl({String? currentPin, String? password}) =>
      _api.post('/parental-control/disable', body: {'current_pin': ?currentPin, 'password': ?password});

  /// Throws an [ApiException] (`pin` field) when wrong, 429 after 5 wrong attempts.
  Future<void> verifyParentalPin(String pin) => _api.post('/parental-control/verify', body: {'pin': pin});
}

/// Code shown by a TV waiting to be signed in.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.verificationUrlComplete,
    required this.expiresIn,
    required this.interval,
  });

  factory DeviceCode.fromJson(Map<String, dynamic> json) => DeviceCode(
    deviceCode: json['device_code'] as String,
    userCode: json['user_code'] as String,
    verificationUrl: json['verification_url'] as String,
    verificationUrlComplete: json['verification_url_complete'] as String,
    expiresIn: Duration(seconds: json['expires_in'] as int? ?? 600),
    interval: Duration(seconds: json['interval'] as int? ?? 5),
  );

  /// Secret: stays on the TV.
  final String deviceCode;

  /// "K7F-29Q".
  final String userCode;
  final String verificationUrl;

  /// Put in the QR code.
  final String verificationUrlComplete;
  final Duration expiresIn;
  final Duration interval;
}
