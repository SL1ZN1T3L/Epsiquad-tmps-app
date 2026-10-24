import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/storage.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class StoragesProvider extends ChangeNotifier {
  StoragesProvider(this._service, {this.onChanged, Stream<String>? events}) {
    // Хранилище создали, изменили или удалили в другом клиенте: список обновляется сам.
    _eventsSubscription = events?.listen((type) {
      if (type != 'storages') return;
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 300), () => unawaited(load(silent: true)));
    });
  }

  final StorageService _service;
  StreamSubscription<String>? _eventsSubscription;
  Timer? _refreshTimer;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _eventsSubscription?.cancel();
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
    if (!silent) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      _items = await _service.list();
      _error = null;
      onChanged?.call(_items);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
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
    final item = await _service.create(plan: plan, ttlHours: ttlHours, title: title, e2eeCheck: e2eeCheck);
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
    removeLocal(code);
    replace(item);
    return item;
  }

  Future<void> remove(String code) async {
    await _service.remove(code);
    removeLocal(code);
  }
}
