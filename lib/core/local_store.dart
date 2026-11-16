import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Settings kept on this device only (notifications…): text by key.
abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

/// The device's protected storage (the one that keeps the session).
class SecureLocalStore implements LocalStore {
  SecureLocalStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

/// For tests.
class MemoryLocalStore implements LocalStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

final localStoreProvider = Provider<LocalStore>((ref) => SecureLocalStore());
