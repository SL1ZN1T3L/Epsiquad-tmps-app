import '../models/config.dart';
import '../models/session.dart';
import 'api_client.dart';

class LoginResult {
  const LoginResult({required this.tokens, required this.user});

  final TokenPair tokens;
  final AppUser user;
}

class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  Map<String, dynamic> _devicePayload(String id, String name, String appVersion) => {
        'id': id,
        'name': name,
        'platform': 'android',
        'app_version': appVersion,
      };

  Future<ServerConfig> config() async {
    final data = await _api.get('$kApiPrefix/config', auth: false);
    return ServerConfig.fromJson(data);
  }

  Future<LoginResult> loginWithPassword({
    required String login,
    required String password,
    required String deviceId,
    required String deviceName,
    required String appVersion,
  }) async {
    final data = await _api.post(
      '$kApiPrefix/auth/password',
      auth: false,
      body: {
        'login': login,
        'password': password,
        'device': _devicePayload(deviceId, deviceName, appVersion),
      },
    );
    return LoginResult(
      tokens: TokenPair.fromJson(data),
      user: AppUser.fromJson((data['user'] as Map<String, dynamic>?) ?? const {}),
    );
  }

  Future<TelegramLogin> telegramStart({
    required String deviceId,
    required String deviceName,
    required String appVersion,
  }) async {
    final data = await _api.post(
      '$kApiPrefix/auth/tg/start',
      auth: false,
      body: {'device': _devicePayload(deviceId, deviceName, appVersion)},
    );
    return TelegramLogin.fromJson(data);
  }

  Future<LoginResult?> telegramClaim({
    required TelegramLogin login,
    required String deviceId,
    required String deviceName,
    required String appVersion,
  }) async {
    final data = await _api.post(
      '$kApiPrefix/auth/tg/claim',
      auth: false,
      body: {
        'token': login.token,
        'nonce': login.nonce,
        'device': _devicePayload(deviceId, deviceName, appVersion),
      },
    );
    final status = data['status'] as String? ?? 'pending';
    if (status == 'pending') return null;
    if (status != 'approved') {
      throw ApiException(
        status == 'declined' ? 'Вход отклонён в боте' : 'Срок подтверждения истёк, начните заново',
      );
    }
    return LoginResult(
      tokens: TokenPair.fromJson(data),
      user: AppUser.fromJson((data['user'] as Map<String, dynamic>?) ?? const {}),
    );
  }

  Future<TokenPair> refresh(String refreshToken) async {
    final data = await _api.post(
      '$kApiPrefix/auth/refresh',
      auth: false,
      body: {'refresh_token': refreshToken},
    );
    return TokenPair.fromJson(data);
  }

  Future<void> logout() => _api.post('$kApiPrefix/auth/logout');

  Future<Profile> me() async {
    final data = await _api.get('$kApiPrefix/me');
    return Profile.fromJson(data);
  }

  Future<List<DeviceEntry>> devices() async {
    final data = await _api.get('$kApiPrefix/devices');
    return ((data['devices'] as List?) ?? const [])
        .map((e) => DeviceEntry.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> revokeDevice(int id) => _api.delete('$kApiPrefix/devices/$id');
}
