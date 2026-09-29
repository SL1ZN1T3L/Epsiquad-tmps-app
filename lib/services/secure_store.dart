import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStore {
  SecureStore({FlutterSecureStorage? storage, LocalAuthentication? auth})

      : _storage = storage ?? const FlutterSecureStorage(),
        _auth = auth ?? LocalAuthentication();

  static const _kRefresh = 'refresh_token';
  static const _kDeviceId = 'device_id';
  static const _kBiometric = 'biometric_enabled';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  Future<String?> readRefreshToken() => _storage.read(key: _kRefresh);

  Future<void> writeRefreshToken(String token) => _storage.write(key: _kRefresh, value: token);

  Future<void> clearRefreshToken() => _storage.delete(key: _kRefresh);

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _kDeviceId);
    if (existing != null && existing.length >= 8) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final generated = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _kDeviceId, value: generated);
    return generated;
  }

  Future<bool> biometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometric) ?? false;
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometric, value);
  }

  Future<bool> biometricAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlock({String reason = 'Подтвердите вход в tmps'}) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}
