import '../models/config.dart';
import '../models/storage.dart';
import 'api_client.dart';

class StorageService {
  StorageService(this._api);

  final ApiClient _api;

  Future<List<StorageItem>> list() async {
    final data = await _api.get('$kApiPrefix/storages');
    return ((data['storages'] as List?) ?? const [])
        .map((e) => StorageItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<PlanInfo>> plans() async {
    final data = await _api.get('$kApiPrefix/plans');
    return ((data['plans'] as List?) ?? const [])
        .map((e) => PlanInfo.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  StorageItem _one(Map<String, dynamic> data) =>
      StorageItem.fromJson((data['storage'] as Map<String, dynamic>?) ?? const {});

  Future<StorageItem> create({required String plan, int? ttlHours, String? title}) async {
    final body = <String, dynamic>{'plan': plan};
    if (ttlHours != null) body['ttl_hours'] = ttlHours;
    if (title != null && title.trim().isNotEmpty) body['title'] = title.trim();
    return _one(await _api.post('$kApiPrefix/storages', body: body));
  }

  Future<StorageItem> get(String code) async => _one(await _api.get('$kApiPrefix/storages/$code'));

  Future<OwnerGrant> ownerGrant(String code) async {
    final data = await _api.post('$kApiPrefix/storages/$code/token');
    return OwnerGrant.fromJson(data);
  }

  Future<StorageItem> extend(String code, int hours) async =>
      _one(await _api.post('$kApiPrefix/storages/$code/extend', body: {'hours': hours}));

  Future<StorageItem> changePlan(String code, String plan) async =>
      _one(await _api.post('$kApiPrefix/storages/$code/plan', body: {'plan': plan}));

  Future<StorageItem> rename(String code, String? title) async =>
      _one(await _api.patch('$kApiPrefix/storages/$code', body: {'title': title}));

  Future<StorageItem> setAccess(String code, String access) async =>
      _one(await _api.patch('$kApiPrefix/storages/$code/access', body: {'access': access}));

  Future<StorageItem> rotate(String code) async =>
      _one(await _api.post('$kApiPrefix/storages/$code/rotate'));

  Future<void> remove(String code) => _api.delete('$kApiPrefix/storages/$code');
}
