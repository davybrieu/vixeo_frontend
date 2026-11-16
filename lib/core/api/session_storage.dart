import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the API token and the last chosen profile are kept between launches.
abstract class SessionStorage {
  Future<String?> readToken();
  Future<void> writeToken(String? token);
  Future<int?> readProfileId();
  Future<void> writeProfileId(int? id);

  /// « Mémoriser le dernier profil » (Paramètres → Avancé): open it at launch. True when never set.
  Future<bool> readRememberProfile();
  Future<void> writeRememberProfile(bool value);
}

/// Keychain (iOS) / Keystore (Android) / encrypted storage (web).
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'vixeo.token';
  static const _profileKey = 'vixeo.profile_id';
  static const _rememberKey = 'vixeo.remember_profile';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String? token) =>
      token == null ? _storage.delete(key: _tokenKey) : _storage.write(key: _tokenKey, value: token);

  @override
  Future<int?> readProfileId() async => int.tryParse(await _storage.read(key: _profileKey) ?? '');

  @override
  Future<void> writeProfileId(int? id) =>
      id == null ? _storage.delete(key: _profileKey) : _storage.write(key: _profileKey, value: '$id');

  @override
  Future<bool> readRememberProfile() async => await _storage.read(key: _rememberKey) != '0';

  @override
  Future<void> writeRememberProfile(bool value) =>
      value ? _storage.delete(key: _rememberKey) : _storage.write(key: _rememberKey, value: '0');
}

/// For tests.
class MemorySessionStorage implements SessionStorage {
  String? token;
  int? profileId;
  bool rememberProfile = true;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String? value) async => token = value;

  @override
  Future<int?> readProfileId() async => profileId;

  @override
  Future<void> writeProfileId(int? id) async => profileId = id;

  @override
  Future<bool> readRememberProfile() async => rememberProfile;

  @override
  Future<void> writeRememberProfile(bool value) async => rememberProfile = value;
}
