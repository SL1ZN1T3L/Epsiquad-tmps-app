import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/config.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/secure_store.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';

enum AppStage { loading, locked, signedOut, ready }

class AppProvider extends ChangeNotifier {
  AppProvider({SecureStore? store, UpdateService? updates})
      : _store = store ?? SecureStore(),
        _updates = updates ?? UpdateService() {
    api = ApiClient(accessToken: () => _tokens?.accessToken, refresh: _refreshTokens);
    auth = AuthService(api);
    storages = StorageService(api);
  }

  final SecureStore _store;
  final UpdateService _updates;

  late final ApiClient api;
  late final AuthService auth;
  late final StorageService storages;

  AppStage _stage = AppStage.loading;
  TokenPair? _tokens;
  AppUser? _user;
  ServerConfig? _config;
  String _deviceId = '';
  String _deviceName = 'Android';
  String _appVersion = '1.0.0';
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String? _notice;
  ReleaseInfo? _update;
  bool _unlockFailed = false;

  AppStage get stage => _stage;
  AppUser? get user => _user;
  ServerConfig? get config => _config;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  String get appVersion => _appVersion;
  String get deviceName => _deviceName;
  String? get notice => _notice;
  bool get unlockFailed => _unlockFailed;
  ReleaseInfo? get update => _update;
  bool get signedIn => _tokens != null && _user != null;

  bool get outdated {
    final cfg = _config;
    if (cfg == null) return false;
    return compareVersions(_appVersion, cfg.minAppVersion) < 0;
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    _stage = AppStage.loading;
    notifyListeners();

    await _readDeviceFacts();
    _deviceId = await _store.deviceId();
    _biometricEnabled = await _store.biometricEnabled();
    _biometricAvailable = await _store.biometricAvailable();

    try {
      _config = await auth.config();
    } catch (_) {
      _notice = 'Не удалось получить настройки сервера. Показаны сохранённые данные';
    }

    final refresh = await _store.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      _stage = AppStage.signedOut;
      notifyListeners();
      return;
    }

    if (_biometricEnabled && _biometricAvailable) {
      _stage = AppStage.locked;
      notifyListeners();
      return;
    }
    await _restore(refresh);
  }

  Future<void> unlock() async {
    _unlockFailed = false;
    if (!await _store.unlock()) {
      _unlockFailed = true;
      _notice = 'Не удалось подтвердить личность';
      notifyListeners();
      return;
    }
    final refresh = await _store.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      _stage = AppStage.signedOut;
      notifyListeners();
      return;
    }
    _stage = AppStage.loading;
    notifyListeners();
    await _restore(refresh);
  }

  Future<void> _restore(String refresh) async {
    try {
      _tokens = await auth.refresh(refresh);
      await _store.writeRefreshToken(_tokens!.refreshToken);
      _applyProfile(await auth.me());
      _notice = null;
      _stage = AppStage.ready;
      unawaited(checkForUpdate());
    } on ApiException catch (e) {
      if (e.unauthorized) {
        await _store.clearRefreshToken();
        _tokens = null;
        _user = null;
        _stage = AppStage.signedOut;
        _notice = 'Нужно войти заново';
      } else {
        _unlockFailed = true;
        _notice = e.message;
        _stage = (_biometricEnabled && _biometricAvailable)
            ? AppStage.locked
            : AppStage.signedOut;
      }
    }
    notifyListeners();
  }

  Future<bool> _refreshTokens() async {
    final current = _tokens?.refreshToken ?? await _store.readRefreshToken();
    if (current == null || current.isEmpty) return false;
    try {
      _tokens = await auth.refresh(current);
      await _store.writeRefreshToken(_tokens!.refreshToken);
      return true;
    } on ApiException {
      await _store.clearRefreshToken();
      _tokens = null;
      _user = null;
      _stage = AppStage.signedOut;
      _notice = 'Сессия закончилась, войдите заново';
      notifyListeners();
      return false;
    }
  }

  Future<void> _readDeviceFacts() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {
      _appVersion = '1.0.0';
    }
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      final model = android.model.trim();
      final brand = android.brand.trim();
      final label = [brand, model].where((p) => p.isNotEmpty).join(' ');
      if (label.isNotEmpty) _deviceName = label;
    } catch (_) {
      _deviceName = 'Android';
    }
  }

  void _applyProfile(Profile profile) {
    _user = profile.user;
    _config = _config?.withPlans(
      profile.plans,
      extend: profile.extendOptions,
      maxActive: profile.maxActive,
    );
  }

  Future<void> signIn(LoginResult result) async {
    _tokens = result.tokens;
    _user = result.user;
    await _store.writeRefreshToken(result.tokens.refreshToken);
    _stage = AppStage.ready;
    notifyListeners();
    unawaited(_syncProfile());
    unawaited(checkForUpdate());
  }

  Future<void> _syncProfile() async {
    try {
      _applyProfile(await auth.me());
      notifyListeners();
    } catch (_) {}
  }

  Future<LoginResult> loginWithPassword(String login, String password) {
    return auth.loginWithPassword(
      login: login,
      password: password,
      deviceId: _deviceId,
      deviceName: _deviceName,
      appVersion: _appVersion,
    );
  }

  Future<TelegramLogin> telegramStart() {
    return auth.telegramStart(
      deviceId: _deviceId,
      deviceName: _deviceName,
      appVersion: _appVersion,
    );
  }

  Future<LoginResult?> telegramClaim(TelegramLogin login) {
    return auth.telegramClaim(
      login: login,
      deviceId: _deviceId,
      deviceName: _deviceName,
      appVersion: _appVersion,
    );
  }

  Future<void> signOut() async {
    try {
      if (_tokens != null) await auth.logout();
    } catch (_) {}
    await _store.clearRefreshToken();
    _tokens = null;
    _user = null;
    _update = null;
    _stage = AppStage.signedOut;
    notifyListeners();
  }

  Future<void> setBiometric(bool value) async {
    if (value && !_biometricAvailable) return;
    if (value && !await _store.unlock(reason: 'Включить вход по биометрии')) return;
    _biometricEnabled = value;
    await _store.setBiometricEnabled(value);
    notifyListeners();
  }

  Future<List<DeviceEntry>> devices() => auth.devices();

  Future<void> revokeDevice(int id) => auth.revokeDevice(id);

  Future<void> checkForUpdate() async {
    final repo = _config?.repoUrl;
    if (repo == null || repo.isEmpty) return;
    final found = await _updates.latest(repoUrl: repo, currentVersion: _appVersion);
    if (found == null) return;
    _update = found;
    notifyListeners();
  }

  @override
  void dispose() {
    api.close();
    _updates.close();
    super.dispose();
  }
}
