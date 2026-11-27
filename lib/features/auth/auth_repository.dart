import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/device/layout.dart';
import 'models.dart';

/// `/auth/*`, `/me` and `/profiles` endpoints.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<String> requestEmailCode({
    required String email,
  }) async => (await _api.post('/auth/email/code', body: {'email': email}))['message'] as String? ?? '';

  Future<({String token, User user, bool created})> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    final json = await _api.post('/auth/email/verify', body: {
      'email': email,
      'code': code,
      'device_name': DeviceInfo.deviceName,
    });
    return (
      token: json['token'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      created: json['created'] as bool? ?? false,
    );
  }

  Future<String> requestEmailLink({
    required String email,
    required String redirectUri,
    required String challenge,
  }) async => (await _api.post('/auth/email/link', body: {
    'email': email,
    'redirect_uri': redirectUri,
    'code_challenge': challenge,
  }))['message'] as String? ?? '';

  /// Creates an account without a password and sends its first sign-in link.
  Future<String> register({
    required String name,
    required String username,
    required String email,
    required String redirectUri,
    required String challenge,
  }) async => (await _api.post('/auth/register', body: {
    'name': name,
    'username': username,
    'email': email,
    'redirect_uri': redirectUri,
    'code_challenge': challenge,
  }))['message'] as String? ?? '';

  Future<({String token, User user})> emailToken({
    required String code,
    required String verifier,
  }) async {
    final json = await _api.post('/auth/email/token', body: {
      'code': code,
      'code_verifier': verifier,
      'device_name': DeviceInfo.deviceName,
    });
    return (token: json['token'] as String, user: User.fromJson(json['user'] as Map<String, dynamic>));
  }

  /// « Continuer avec Google / Apple »: whether the server has the settings of each provider.
  Future<Map<String, bool>> socialProviders() async {
    final json = await _api.get('/auth/social');
    return {
      for (final entry in (json['data'] as List? ?? const []).cast<Map<String, dynamic>>())
        entry['provider'] as String: entry['available'] as bool? ?? false,
    };
  }

  /// The token of a sign-in with Google or Apple: the code the browser brought back and the
  /// secret of its challenge (vixeo_backend/docs/connexion-sociale.md).
  Future<({String token, User user, bool created})> socialToken({
    required String code,
    required String verifier,
  }) async {
    final json = await _api.post(
      '/auth/social/token',
      body: {'code': code, 'code_verifier': verifier, 'device_name': DeviceInfo.deviceName},
    );
    return (
      token: json['token'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      created: json['created'] as bool? ?? false,
    );
  }

  Future<User> me() async => User.fromJson((await _api.get('/me'))['data'] as Map<String, dynamic>);

  // ── Account: devices, data, deletion ──

  Future<List<Device>> devices() async {
    final json = await _api.get('/me/devices');
    return (json['data'] as List).cast<Map<String, dynamic>>().map(Device.fromJson).toList();
  }

  Future<void> revokeDevice(int id) => _api.delete('/me/devices/$id');

  /// E-mails the account's data (JSON). Returns the API's message.
  Future<String> exportData() async => (await _api.post('/me/export'))['message'] as String? ?? '';

  /// Requests a one-time confirmation link before changing the sign-in e-mail address.
  Future<String> updateEmail({
    required String email,
    required String redirectUri,
    required String challenge,
  }) async => (await _api.post('/me/email', body: {
    'email': email,
    'redirect_uri': redirectUri,
    'code_challenge': challenge,
  }))['message'] as String? ?? '';

  /// Deletes the account; the authenticated session confirms the action.
  Future<void> deleteAccount() => _api.post('/me/delete');

  Future<void> logout() => _api.post('/auth/logout');

  Future<List<Profile>> profiles() async {
    final json = await _api.get('/profiles');
    return (json['data'] as List).cast<Map<String, dynamic>>().map(Profile.fromJson).toList();
  }

  /// The profile's own photo (a framed square, PNG), shown instead of its avatar
  /// (vixeo_backend/docs/social.md).
  Future<Profile> uploadProfilePhoto(int profileId, Uint8List png) async {
    final json = await _api.upload(
      '/profiles/$profileId/photo',
      field: 'photo',
      stream: () => Stream.value(png),
      length: png.length,
      filename: 'photo.png',
    );
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Back to the avatar.
  Future<Profile> deleteProfilePhoto(int profileId) async {
    final json = await _api.delete('/profiles/$profileId/photo');
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Its own cover image (a 3:1 PNG framed on the device), instead of its cover of the catalog.
  Future<Profile> uploadProfileCover(int profileId, Uint8List png) async {
    final json = await _api.upload(
      '/profiles/$profileId/cover',
      field: 'cover',
      stream: () => Stream.value(png),
      length: png.length,
      filename: 'cover.png',
    );
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Back to its cover of the catalog.
  Future<Profile> deleteProfileCover(int profileId) async {
    final json = await _api.delete('/profiles/$profileId/cover');
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Changes harmless profile fields (`name`, `avatar`, `poster_format`…).
  Future<Profile> updateProfile(int profileId, Map<String, Object?> fields) async {
    final json = await _api.patch('/profiles/$profileId', body: fields);
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

  // ── TV sign-in with a code (vixeo_backend/docs/connexion-tv.md) ──

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


}

/// Code shown by a TV waiting to be signed in.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.expiresIn,
    required this.interval,
  });

  factory DeviceCode.fromJson(Map<String, dynamic> json) => DeviceCode(
    deviceCode: json['device_code'] as String,
    userCode: json['user_code'] as String,
    expiresIn: Duration(seconds: json['expires_in'] as int? ?? 600),
    interval: Duration(seconds: json['interval'] as int? ?? 5),
  );

  /// Secret: stays on the TV.
  final String deviceCode;

  /// "K7F-29Q": shown on the TV, typed in the phone's app (« Connecter une TV »). No QR code
  /// (developer's request): the API's verification links are left aside.
  final String userCode;
  final Duration expiresIn;
  final Duration interval;
}
