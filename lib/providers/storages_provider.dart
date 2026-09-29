import 'package:flutter/foundation.dart';

import '../models/storage.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';

class StoragesProvider extends ChangeNotifier {
  StoragesProvider(this._service);

  final StorageService _service;

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
  }

  void removeLocal(String code) {
    _items = _items.where((s) => s.code != code).toList(growable: false);
    notifyListeners();
  }

  Future<StorageItem> create({required String plan, int? ttlHours, String? title}) async {
    final item = await _service.create(plan: plan, ttlHours: ttlHours, title: title);
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
