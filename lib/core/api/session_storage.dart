import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the API token is kept between launches.
abstract class SessionStorage {
  Future<String?> readToken();
  Future<void> writeToken(String? token);
}

/// Keychain (iOS) / Keystore (Android) / Credential Manager (Windows).
class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'vixeo.token';

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String? token) =>
      token == null ? _storage.delete(key: _tokenKey) : _storage.write(key: _tokenKey, value: token);

}

/// For tests.
class MemorySessionStorage implements SessionStorage {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String? value) async => token = value;

}
