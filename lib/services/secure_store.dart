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
  static const _kE2eePrefix = 'e2ee.key.';
  static const _kUploadPrefix = 'upload.v1.';
  static const _kDownloadPrefix = 'download.v1.';

  static const int iterations = 120000;
  static const int maxAttempts = 10;
  static const int pinLength = 4;

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  final _gcm = AesGcm.with256bits();

  SecretKey? _key;
  int _wipeGeneration = 0;

  bool get unlocked => _key != null;
  int get wipeGeneration => _wipeGeneration;

  void lock() => _key = null;

  Future<bool> hasPin() async => (await _storage.read(key: _kCheck)) != null;

  Future<int> failedAttempts() async {
    final raw = await _storage.read(key: _kFails);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<SecretKey> _derive(String pin, List<int> salt) {
    final kdf =
        Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
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
    if (await biometricEnabled()) {
      await _storage.write(key: _kMirror, value: pin);
    }
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

  Future<bool> openWithBiometrics(
      {String reason = 'Подтвердите вход в tmps'}) async {
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
      final box = SecretBox.fromConcatenation(base64Decode(raw),
          nonceLength: 12, macLength: 16);
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

  // ---- Ключи сквозного шифрования хранилищ ----

  /// Ключ E2EE-хранилища (base64url). Лежит в защищённом хранилище Android, по одному на код хранилища.
  Future<String?> readE2eeKey(String code) =>
      _storage.read(key: '$_kE2eePrefix$code');

  Future<void> writeE2eeKey(String code, String key) =>
      _storage.write(key: '$_kE2eePrefix$code', value: key);

  Future<void> deleteE2eeKey(String code) =>
      _storage.delete(key: '$_kE2eePrefix$code');

  Future<bool> hasE2eeKeys() async {
    try {
      final all = await _storage.readAll();
      return all.keys.any((key) => key.startsWith(_kE2eePrefix));
    } catch (_) {
      return false;
    }
  }

  /// Смена кода хранилища не должна отрезать устройство от его E2EE-ключа.
  /// Сначала записываем новую копию, и только потом удаляем старую.
  Future<void> moveE2eeKey(String oldCode, String newCode) async {
    if (oldCode == newCode) return;
    final key = await readE2eeKey(oldCode);
    if (key == null) return;
    await writeE2eeKey(newCode, key);
    await deleteE2eeKey(oldCode);
  }

  // ---- Восстановление передач ----

  /// Метаданные загрузок содержат локальные пути и E2EE-имена, поэтому хранятся
  /// только здесь, а не в обычных SharedPreferences.
  Future<List<Map<String, dynamic>>> readUploadTasks(String code) async {
    final raw = await _storage.read(key: '$_kUploadPrefix$code');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (entry is Map) Map<String, dynamic>.from(entry),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeUploadTasks(
      String code, List<Map<String, dynamic>> tasks) async {
    final key = '$_kUploadPrefix$code';
    if (tasks.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: jsonEncode(tasks));
    }
  }

  Future<void> deleteUploadTasks(String code) =>
      _storage.delete(key: '$_kUploadPrefix$code');

  Future<List<Map<String, dynamic>>> readDownloadRecords() async {
    final all = await _storage.readAll();
    final records = <Map<String, dynamic>>[];
    for (final entry in all.entries) {
      if (!entry.key.startsWith(_kDownloadPrefix)) continue;
      try {
        final decoded = jsonDecode(entry.value);
        if (decoded is Map) records.add(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    return records;
  }

  Future<Map<String, dynamic>?> readDownloadRecord(String taskId) async {
    final raw = await _storage.read(key: '$_kDownloadPrefix$taskId');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDownloadRecord(
          String taskId, Map<String, dynamic> record) =>
      _storage.write(
          key: '$_kDownloadPrefix$taskId', value: jsonEncode(record));

  Future<void> deleteDownloadRecord(String taskId) =>
      _storage.delete(key: '$_kDownloadPrefix$taskId');

  Future<void> moveStorageData(String oldCode, String newCode) async {
    if (oldCode == newCode) return;
    await moveE2eeKey(oldCode, newCode);
    final uploads = await readUploadTasks(oldCode);
    if (uploads.isNotEmpty) {
      await writeUploadTasks(newCode, uploads);
    }
    await deleteUploadTasks(oldCode);
    final downloads = await readDownloadRecords();
    for (final record in downloads) {
      if (record['storageCode'] != oldCode) continue;
      final taskId = record['taskId'];
      if (taskId is! String) continue;
      await writeDownloadRecord(taskId, {...record, 'storageCode': newCode});
    }
  }

  Future<void> deleteStorageData(String code) async {
    await deleteE2eeKey(code);
    await deleteUploadTasks(code);
    final downloads = await readDownloadRecords();
    for (final record in downloads) {
      if (record['storageCode'] != code) continue;
      final taskId = record['taskId'];
      if (taskId is String) await deleteDownloadRecord(taskId);
    }
  }

  Future<void> _wipeTransferData() async {
    try {
      final all = await _storage.readAll();
      for (final key in all.keys) {
        if (key.startsWith(_kE2eePrefix) ||
            key.startsWith(_kUploadPrefix) ||
            key.startsWith(_kDownloadPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (_) {}
  }

  Future<void> wipe() async {
    _wipeGeneration++;
    _key = null;
    for (final key in [_kBox, _kSalt, _kCheck, _kMirror, _kFails]) {
      await _storage.delete(key: key);
    }
    await _wipeTransferData();
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
