import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kToken = 'ziggo_token';
  static const _kRole = 'ziggo_role';
  static const _kUserId = 'ziggo_user_id';

  static Future<void> save({
    required String token,
    required String role,
    required int userId,
  }) async {
    await _storage.write(key: _kToken, value: token);
    await _storage.write(key: _kRole, value: role);
    await _storage.write(key: _kUserId, value: userId.toString());
  }

  static Future<String?> getToken() => _storage.read(key: _kToken);
  static Future<String?> getRole() => _storage.read(key: _kRole);

  static Future<int?> getUserId() async {
    final v = await _storage.read(key: _kUserId);
    return v == null ? null : int.tryParse(v);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kRole);
    await _storage.delete(key: _kUserId);
  }
}
