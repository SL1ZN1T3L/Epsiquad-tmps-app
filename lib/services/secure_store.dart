import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinLocked implements Exception {
  PinLocked(this.left);

  final int left;
}

class SecureStore {
  SecureStore({FlutterSecureStorage? storage, LocalAuthentication? auth})
      : _storage = storage ?? const FlutterSecureStorage(),
        _auth = auth ?? LocalAuthentication();

  static const _kBox = 'refresh_box';
  static const _kSalt = 'pin_salt';
  static const _kCheck = 'pin_check';
  static const _kMirror = 'pin_mirror';
  static const _kFails = 'pin_fails';
  static const _kDeviceId = 'device_id';
  static const _kBiometric = 'biometric_enabled';

  static const int iterations = 120000;
  static const int maxAttempts = 10;
  static const int pinLength = 4;

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  final _gcm = AesGcm.with256bits();

  SecretKey? _key;

  bool get unlocked => _key != null;

  void lock() => _key = null;

  Future<bool> hasPin() async => (await _storage.read(key: _kCheck)) != null;

  Future<int> failedAttempts() async {
    final raw = await _storage.read(key: _kFails);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<SecretKey> _derive(String pin, List<int> salt) {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    return kdf.deriveKeyFromPassword(password: pin, nonce: salt);
  }

  Future<String> _verifier(SecretKey key) async {
    final bytes = await key.extractBytes();
    return base64Encode(hashing.sha256.convert(bytes).bytes);
  }

  List<int> _randomBytes(int count) {
    final random = Random.secure();
    return List<int>.generate(count, (_) => random.nextInt(256));
  }

  Future<void> setPin(String pin, {required String refreshToken}) async {
    final salt = _randomBytes(16);
    final key = await _derive(pin, salt);
    await _storage.write(key: _kSalt, value: base64Encode(salt));
    await _storage.write(key: _kCheck, value: await _verifier(key));
    await _storage.delete(key: _kFails);
    _key = key;
    await writeRefreshToken(refreshToken);
    if (await biometricEnabled()) await _storage.write(key: _kMirror, value: pin);
  }

  Future<bool> openWithPin(String pin) async {
    final saltRaw = await _storage.read(key: _kSalt);
    final check = await _storage.read(key: _kCheck);
    if (saltRaw == null || check == null) return false;
    final key = await _derive(pin, base64Decode(saltRaw));
    if (await _verifier(key) != check) {
      final fails = await failedAttempts() + 1;
      await _storage.write(key: _kFails, value: '$fails');
      if (fails >= maxAttempts) {
        await wipe();
        throw PinLocked(0);
      }
      return false;
    }
    await _storage.delete(key: _kFails);
    _key = key;
    return true;
  }

  Future<bool> openWithBiometrics({String reason = 'Подтвердите вход в tmps'}) async {
    if (!await authenticate(reason: reason)) return false;
    final pin = await _storage.read(key: _kMirror);
    if (pin == null) return false;
    return openWithPin(pin);
  }

  Future<String?> readRefreshToken() async {
    final key = _key;
    final raw = await _storage.read(key: _kBox);
    if (key == null || raw == null) return null;
    try {
      final box = SecretBox.fromConcatenation(base64Decode(raw), nonceLength: 12, macLength: 16);
      final clear = await _gcm.decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeRefreshToken(String token) async {
    final key = _key;
    if (key == null) return;
    final box = await _gcm.encrypt(utf8.encode(token), secretKey: key);
    await _storage.write(key: _kBox, value: base64Encode(box.concatenation()));
  }

  Future<void> clearRefreshToken() => _storage.delete(key: _kBox);

  Future<void> wipe() async {
    _key = null;
    for (final key in [_kBox, _kSalt, _kCheck, _kMirror, _kFails]) {
      await _storage.delete(key: key);
    }
    await setBiometricEnabled(false);
  }

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _kDeviceId);
    if (existing != null && existing.length >= 8) return existing;
    final generated =
        _randomBytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _storage.write(key: _kDeviceId, value: generated);
    return generated;
  }

  Future<bool> biometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometric) ?? false;
  }

  Future<void> setBiometricEnabled(bool value, {String? pin}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometric, value);
    if (value && pin != null) {
      await _storage.write(key: _kMirror, value: pin);
    } else if (!value) {
      await _storage.delete(key: _kMirror);
    }
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

  Future<bool> authenticate({String reason = 'Подтвердите вход в tmps'}) async {
    try {
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}
