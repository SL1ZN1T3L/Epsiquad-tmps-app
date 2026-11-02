import '../models/config.dart';
import '../models/storage.dart';
import 'api_client.dart';

class StorageService {
  StorageService(this._api);

  final ApiClient _api;

  Future<List<StorageItem>> list() async {
    final data = await _api.operation('my_storages');
    return ((data['storages'] as List?) ?? const [])
        .map((e) => StorageItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<PlanInfo>> plans() async {
    final data = await _api.operation('list_plans');
    return ((data['plans'] as List?) ?? const [])
        .map((e) => PlanInfo.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  StorageItem _one(Map<String, dynamic> data) =>
      StorageItem.fromJson((data['storage'] as Map<String, dynamic>?) ?? const {});

  Future<StorageItem> create({
    required String plan,
    int? ttlHours,
    String? title,
    String? e2eeCheck,
  }) async {
    final body = <String, dynamic>{'plan': plan};
    if (ttlHours != null) body['ttl_hours'] = ttlHours;
    if (title != null && title.trim().isNotEmpty) body['title'] = title.trim();
    if (e2eeCheck != null) body['e2ee_check'] = e2eeCheck;
    return _one(await _api.operation('create_storage', body: body));
  }

  Future<StorageItem> get(String code) async =>
      _one(await _api.operation('one_storage', parameters: {'code': code}));

  Future<OwnerGrant> ownerGrant(String code) async {
    final data = await _api.operation('storage_token', parameters: {'code': code});
    return OwnerGrant.fromJson(data);
  }

  Future<StorageItem> extend(String code, int hours) async => _one(await _api.operation(
        'extend',
        parameters: {'code': code},
        body: {'hours': hours},
      ));

  Future<StorageItem> changePlan(String code, String plan) async => _one(await _api.operation(
        'change_plan',
        parameters: {'code': code},
        body: {'plan': plan},
      ));

  Future<StorageItem> rename(String code, String? title) async => _one(await _api.operation(
        'rename',
        parameters: {'code': code},
        body: {'title': title},
      ));

  Future<StorageItem> setAccess(String code, String access) async => _one(await _api.operation(
        'set_access',
        parameters: {'code': code},
        body: {'access': access},
      ));

  /// Задаёт пароль на вход по ссылке; null убирает пароль.
  Future<StorageItem> setPassword(String code, String? password) async => _one(await _api.operation(
        'set_password',
        parameters: {'code': code},
        body: {'password': password},
      ));

  Future<StorageItem> rotate(String code) async =>
      _one(await _api.operation('rotate', parameters: {'code': code}));

  Future<void> remove(String code) =>
      _api.operation('delete_storage', parameters: {'code': code});
}
