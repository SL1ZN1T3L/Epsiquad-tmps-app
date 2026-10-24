import 'dart:async';
import 'dart:developer' as developer;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/config.dart';
import '../models/session.dart';
import '../models/storage.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../services/reminder_service.dart';
import '../services/secure_store.dart';
import '../services/share_inbox.dart';
import '../services/system_service.dart';
import '../services/user_events.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';

enum AppStage { loading, locked, pinSetup, signedOut, ready }

class AppProvider extends ChangeNotifier {
  AppProvider({SecureStore? store, UpdateService? updates})
      : _store = store ?? SecureStore(),
        _updates = updates ?? UpdateService() {
    api = ApiClient(
        accessToken: () => _tokens?.accessToken, refresh: _refreshTokens);
    auth = AuthService(api);
    storages = StorageService(api);
  }

  final SecureStore _store;
  final UpdateService _updates;

  late final ApiClient api;
  late final AuthService auth;
  late final StorageService storages;

  AppStage _stage = AppStage.loading;

  // ---- События аккаунта в реальном времени ----
  // Канал открыт, пока приложение разблокировано и вход выполнен: в других клиентах создали хранилище, вошли в аккаунт,
  // отключили устройство - экраны обновляются сами.
  final StreamController<String> _events = StreamController<String>.broadcast();
  UserEvents? _liveChannel;

  /// События аккаунта: `storages`, `devices`, `account`. После восстановления связи приходят все три.
  Stream<String> get events => _events.stream;

  @override
  void notifyListeners() {
    super.notifyListeners();
    _syncLiveChannel();
  }

  void _syncLiveChannel() {
    final shouldRun = _stage == AppStage.ready && _tokens != null && !_autoLocked;
    if (shouldRun && _liveChannel == null) {
      _liveChannel = UserEvents(
        token: () => _tokens?.accessToken,
        onEvent: (type) {
          if (!_events.isClosed) _events.add(type);
          if (type == 'account') unawaited(_refreshProfile());
        },
        onReconnect: () {
          for (final type in const ['storages', 'devices', 'account']) {
            if (!_events.isClosed) _events.add(type);
          }
        },
        ensureToken: () => auth.devices().then((_) {}),
      )..start();
    } else if (!shouldRun && _liveChannel != null) {
      _liveChannel!.stop();
      _liveChannel = null;
    }
  }

  /// Данные аккаунта изменились в другом клиенте (пароль, Telegram, ключи доступа).
  Future<void> _refreshProfile() async {
    try {
      final profile = await auth.me();
      _user = profile.user;
      super.notifyListeners();
    } catch (_) {}
  }

  TokenPair? _tokens;
  AppUser? _user;
  ServerConfig? _config;
  String _deviceId = '';
  String _deviceName = 'Android';
  List<String> _abis = const [];
  String _appVersion = '1.0.0';
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _devMode = false;
  bool _autoBiometricEnabled = true;
  String? _notice;
  ReleaseInfo? _update;

  // Настройки безопасности и напоминаний
  static const _kAutoLock = 'tmps_auto_lock_minutes';
  static const _kExpiryLead = 'tmps_expiry_lead_hours';
  int _autoLockMinutes = 5;
  bool _hideRecents = true;
  int _expiryLeadHours = 24;
  bool _autoLocked = false;
  DateTime _lastActive = DateTime.now();
  int _lockHolds = 0;
  bool _shareStarted = false;
  List<SharedFile> _pendingShare = const [];
  List<StorageItem> _knownStorages = const [];

  AppStage get stage => _stage;
  AppUser? get user => _user;
  ServerConfig? get config => _config;

  /// Защищённое хранилище устройства: в нём лежат ключи E2EE-хранилищ.
  SecureStore get secureStore => _store;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  bool get autoBiometricEnabled => _autoBiometricEnabled;
  String get appVersion => _appVersion;
  String get deviceName => _deviceName;
  List<String> get abis => _abis;
  UpdateService get updates => _updates;
  String? get notice => _notice;
  ReleaseInfo? get update => _update;
  bool get signedIn => _tokens != null && _user != null;
  bool get devMode => _devMode;
  int get autoLockMinutes => _autoLockMinutes;
  bool get hideRecents => _hideRecents;
  int get expiryLeadHours => _expiryLeadHours;
  bool get autoLocked => _autoLocked;
  List<SharedFile> get pendingShare => _pendingShare;

  bool get outdated {
    final cfg = _config;
    if (cfg == null) return false;
    return compareVersions(_appVersion, cfg.minAppVersion) < 0;
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }

  // ---- Настройки ----

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoLockMinutes = prefs.getInt(_kAutoLock) ?? 5;
      _hideRecents = prefs.getBool(SystemService.hideRecentsKey) ?? true;
      _expiryLeadHours = prefs.getInt(_kExpiryLead) ?? 24;
    } catch (_) {}
    unawaited(SystemService.setHideRecents(_hideRecents));
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    _autoLockMinutes = minutes;
    _lastActive = DateTime.now();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAutoLock, minutes);
    } catch (_) {}
  }

  Future<void> setHideRecents(bool value) async {
    _hideRecents = value;
    notifyListeners();
    await SystemService.setHideRecents(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SystemService.hideRecentsKey, value);
    } catch (_) {}
  }

  Future<void> setExpiryLeadHours(int hours) async {
    _expiryLeadHours = hours;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kExpiryLead, hours);
    } catch (_) {}
    if (hours > 0) await DownloadService.requestNotificationPermission();
    await syncReminders(_knownStorages);
  }

  /// Вызывается при каждом обновлении списка хранилищ.
  Future<void> syncReminders(List<StorageItem> items) async {
    _knownStorages = items;
    await ReminderService.sync(items, leadHours: _expiryLeadHours);
  }

  // ---- Автоблокировка по таймеру ----

  /// Любое касание экрана сбрасывает отсчёт.
  void touch() => _lastActive = DateTime.now();

  /// Пока открыт плеер, блокировка по таймеру не срабатывает.
  void holdLock() => _lockHolds++;

  void releaseLock() {
    if (_lockHolds > 0) _lockHolds--;
    _lastActive = DateTime.now();
  }

  void checkAutoLock() {
    if (_stage != AppStage.ready || _autoLocked) return;
    if (_autoLockMinutes <= 0 || _lockHolds > 0) return;
    if (DateTime.now().difference(_lastActive) >= Duration(minutes: _autoLockMinutes)) {
      lockNow();
    }
  }

  /// Закрывает приложение пин-кодом, не разрушая открытые экраны:
  /// загрузки и скачивания продолжаются.
  void lockNow() {
    if (_stage != AppStage.ready || _autoLocked) return;
    _store.lock();
    _autoLocked = true;
    _autoBiometricEnabled = true;
    notifyListeners();
  }

  Future<String?> relockWithPin(String pin) async {
    try {
      if (!await _store.openWithPin(pin)) {
        final left = SecureStore.maxAttempts - await _store.failedAttempts();
        return left <= 3
            ? 'Неверный пин-код, осталось попыток: $left'
            : 'Неверный пин-код';
      }
    } on PinLocked {
      _afterWipe();
      return 'Слишком много попыток. Данные входа стёрты, войдите заново';
    }
    _finishRelock();
    return null;
  }

  Future<String?> relockWithBiometrics() async {
    try {
      if (!await _store.openWithBiometrics()) return null;
    } on PinLocked {
      _afterWipe();
      return 'Слишком много попыток. Данные входа стёрты, войдите заново';
    }
    _finishRelock();
    return null;
  }

  void _finishRelock() {
    _autoLocked = false;
    _lastActive = DateTime.now();
    notifyListeners();
  }

  // ---- Файлы из «Поделиться» ----

  void _onShared(List<SharedFile> files) {
    if (files.isEmpty) return;
    _pendingShare = [..._pendingShare, ...files];
    notifyListeners();
  }

  List<SharedFile> takeShare() {
    final taken = _pendingShare;
    _pendingShare = const [];
    return taken;
  }

  Future<void> bootstrap() async {
    _stage = AppStage.loading;
    _autoBiometricEnabled = true;
    notifyListeners();

    await _readDeviceFacts();
    await _loadSettings();
    if (!_shareStarted) {
      _shareStarted = true;
      unawaited(ShareInbox.start(_onShared));
    }
    _deviceId = await _store.deviceId();
    _biometricEnabled = await _store.biometricEnabled();
    _biometricAvailable = await _store.biometricAvailable();

    try {
      _config = await auth.config();
    } catch (_) {
      _notice =
          'Не удалось получить настройки сервера. Показаны сохранённые данные';
    }

    _stage = await _store.hasPin() ? AppStage.locked : AppStage.signedOut;
    notifyListeners();
  }

  Future<String?> unlockWithPin(String pin) async {
    try {
      if (!await _store.openWithPin(pin)) {
        final left = SecureStore.maxAttempts - await _store.failedAttempts();
        return left <= 3
            ? 'Неверный пин-код, осталось попыток: $left'
            : 'Неверный пин-код';
      }
    } on PinLocked {
      _afterWipe();
      return 'Слишком много попыток. Данные входа стёрты, войдите заново';
    }
    await _afterUnlock();
    return null;
  }

  Future<String?> unlockWithBiometrics() async {
    try {
      if (!await _store.openWithBiometrics()) return null;
    } on PinLocked {
      _afterWipe();
      return 'Слишком много попыток. Данные входа стёрты, войдите заново';
    }
    await _afterUnlock();
    return null;
  }

  Future<void> _afterUnlock() async {
    final refresh = await _store.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      await _store.wipe();
      _biometricEnabled = false;
      _stage = AppStage.signedOut;
      _notice = 'Нужно войти заново';
      notifyListeners();
      return;
    }
    _stage = AppStage.loading;
    notifyListeners();
    await _restore(refresh);
  }

  void _afterWipe() {
    _autoLocked = false;
    _biometricEnabled = false;
    _tokens = null;
    _user = null;
    _stage = AppStage.signedOut;
    notifyListeners();
  }

  Future<String?> definePin(String pin) async {
    final tokens = _tokens;
    if (tokens == null) return 'Сессия потерялась, войдите заново';
    await _store.setPin(pin, refreshToken: tokens.refreshToken);
    _stage = AppStage.ready;
    notifyListeners();
    unawaited(_syncProfile());
    unawaited(checkForUpdate());
    return null;
  }

  Future<String?> changePin(String current, String next) async {
    try {
      if (!await _store.openWithPin(current)) {
        return 'Текущий пин-код не подошёл';
      }
    } on PinLocked {
      _afterWipe();
      return 'Слишком много попыток. Данные входа стёрты, войдите заново';
    }
    final refresh = await _store.readRefreshToken();
    if (refresh == null) return 'Не удалось прочитать данные входа';
    await _store.setPin(next, refreshToken: refresh);
    return null;
  }

  Future<void> _restore(String refresh) async {
    try {
      _tokens = await auth.refresh(
        refresh,
        deviceId: _deviceId,
        deviceName: _deviceName,
        appVersion: _appVersion,
      );
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
        developer.log(
          'Restoring the saved session failed',
          name: 'tmps.auth',
          error: e,
        );
        _notice = e.message;
        _autoBiometricEnabled = false;
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
      _tokens = await auth.refresh(
        current,
        deviceId: _deviceId,
        deviceName: _deviceName,
        appVersion: _appVersion,
      );
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
      _abis = android.supportedAbis;
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
    if (_store.unlocked) {
      await _store.writeRefreshToken(result.tokens.refreshToken);
      _stage = AppStage.ready;
      notifyListeners();
      unawaited(_syncProfile());
      unawaited(checkForUpdate());
      return;
    }
    _stage = AppStage.pinSetup;
    notifyListeners();
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
    await _store.wipe();
    _autoLocked = false;
    _pendingShare = const [];
    _knownStorages = const [];
    unawaited(ReminderService.cancelAll());
    _biometricEnabled = false;
    _tokens = null;
    _user = null;
    _update = null;
    await setDevMode(false);
    _stage = AppStage.signedOut;
    notifyListeners();
  }

  Future<String?> setBiometric(bool value, {String? pin}) async {
    if (value) {
      if (!_biometricAvailable) return 'Биометрия на этом телефоне недоступна';
      if (pin == null) return 'Нужен пин-код';
      try {
        if (!await _store.openWithPin(pin)) return 'Пин-код не подошёл';
      } on PinLocked {
        _afterWipe();
        return 'Слишком много попыток. Данные входа стёрты, войдите заново';
      }
      if (!await _store.authenticate(reason: 'Включить вход по отпечатку')) {
        return 'Не удалось подтвердить личность';
      }
    }
    _biometricEnabled = value;
    await _store.setBiometricEnabled(value, pin: pin);
    notifyListeners();
    return null;
  }

  Future<List<DeviceEntry>> devices() => auth.devices();

  Future<void> revokeDevice(int id) => auth.revokeDevice(id);

  Future<void> checkForUpdate() async {
    if (_devMode) return;
    final repo = _config?.repoUrl;
    if (repo == null || repo.isEmpty) return;
    final found =
        await _updates.latest(repoUrl: repo, currentVersion: _appVersion);
    if (found == null) return;
    _update = found;
    notifyListeners();
  }

  Future<void> setDevMode(bool value) async {
    _devMode = value;
    api.setOffline(value);
    notifyListeners();
  }

  @override
  void dispose() {
    _liveChannel?.stop();
    _liveChannel = null;
    unawaited(_events.close());
    api.close();
    _updates.close();
    super.dispose();
  }
}
