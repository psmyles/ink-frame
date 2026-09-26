import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small key-value store for sessions and the list of frames. Secure storage in
/// the app; in memory in tests.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStore implements KeyValueStore {
  SecureStore()
      : _storage = const FlutterSecureStorage(
          // The legacy file-based keychain works for unsigned debug builds; the data
          // protection keychain needs a signed app with a keychain entitlement.
          mOptions: MacOsOptions(usesDataProtectionKeychain: false),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}
