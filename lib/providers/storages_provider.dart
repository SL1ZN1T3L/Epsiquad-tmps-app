import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/storage.dart';
import '../services/api_client.dart';
import '../services/download_service.dart';
import '../services/node_service.dart';
import '../services/secure_store.dart';
import '../services/storage_service.dart';
import 'storage_provider.dart';

class StoragesProvider extends ChangeNotifier {
  StoragesProvider(
    this._service, {
    this.onChanged,
    Stream<String>? events,
    SecureStore? secure,
  }) : _secure = secure ?? SecureStore() {
    // Хранилище создали, изменили или удалили в другом клиенте: список обновляется сам.
    _eventsSubscription = events?.listen((type) {
      if (type != 'storages') return;
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 300),
          () => unawaited(load(silent: true)));
    });
  }

  final StorageService _service;
  final SecureStore _secure;
  StreamSubscription<String>? _eventsSubscription;
  Timer? _refreshTimer;
  final Map<String, StorageProvider> _sessions = {};
  int _loadGeneration = 0;
  bool _disposed = false;

  /// Один живой provider на хранилище: выход из Route не останавливает передачи.
  StorageProvider providerFor(StorageItem item) {
    final existing = _sessions[item.code];
    if (existing != null) {
      existing.applyItem(item);
      return existing;
    }
    final created = StorageProvider(
      storages: _service,
      node: NodeService(),
      initial: item,
      secure: _secure,
    );
    _sessions[item.code] = created;
    unawaited(created.initialize());
    return created;
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _refreshTimer?.cancel();
    _eventsSubscription?.cancel();
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    super.dispose();
  }

  /// Вызывается после каждого изменения списка: по нему обновляются
  /// напоминания об истечении срока.
  final void Function(List<StorageItem> items)? onChanged;

  List<StorageItem> _items = const [];
  bool _loading = false;
  String? _error;

  List<StorageItem> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    if (!silent) {
      _loading = true;
      _error = null;
      if (!_disposed) notifyListeners();
    }
    try {
      final items = await _service.list();
      if (_disposed || generation != _loadGeneration) return;
      _items = items;
      _error = null;
      onChanged?.call(_items);
    } on ApiException catch (e) {
      if (!_disposed && generation == _loadGeneration) _error = e.message;
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void replace(StorageItem item) {
    final index = _items.indexWhere((s) => s.code == item.code);
    if (index < 0) {
      _items = [item, ..._items];
    } else {
      final copy = [..._items];
      copy[index] = item;
      _items = copy;
    }
    notifyListeners();
    onChanged?.call(_items);
  }

  void removeLocal(String code) {
    _items = _items.where((s) => s.code != code).toList(growable: false);
    notifyListeners();
    onChanged?.call(_items);
  }

  Future<StorageItem> create({
    required String plan,
    int? ttlHours,
    String? title,
    String? e2eeCheck,
  }) async {
    final item = await _service.create(
        plan: plan, ttlHours: ttlHours, title: title, e2eeCheck: e2eeCheck);
    replace(item);
    return item;
  }

  Future<StorageItem> setPassword(String code, String? password) async {
    final item = await _service.setPassword(code, password);
    replace(item);
    return item;
  }

  Future<StorageItem> extend(String code, int hours) async {
    final item = await _service.extend(code, hours);
    replace(item);
    return item;
  }

  Future<StorageItem> changePlan(String code, String plan) async {
    final item = await _service.changePlan(code, plan);
    replace(item);
    return item;
  }

  Future<StorageItem> rename(String code, String? title) async {
    final item = await _service.rename(code, title);
    replace(item);
    return item;
  }

  Future<StorageItem> setAccess(String code, String access) async {
    final item = await _service.setAccess(code, access);
    replace(item);
    return item;
  }

  Future<StorageItem> rotate(String code) async {
    final item = await _service.rotate(code);
    Object? migrationError;
    try {
      await _secure.moveStorageData(code, item.code);
    } catch (error) {
      migrationError = error;
    }

    final session = _sessions.remove(code);
    if (session != null) {
      session.applyRotatedItem(item);
      _sessions[item.code] = session;
    }
    removeLocal(code);
    replace(item);
    if (migrationError != null) {
      throw ApiException(
        'Ссылка изменена, но локальные данные перенесены не полностью. '
        'Не закрывайте приложение и проверьте ключ шифрования и передачи',
      );
    }
    return item;
  }

  Future<void> remove(String code) async {
    await _service.remove(code);
    final session = _sessions.remove(code);
    if (session != null) {
      await session.cancelAll();
      await session.cancelAllDownloads();
      session.dispose();
    }
    await DownloadService.cancelStorage(code);
    try {
      await _secure.deleteStorageData(code);
    } catch (_) {}
    removeLocal(code);
  }
}
