import 'config.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.login,
    required this.displayName,
    required this.tgId,
    required this.tgUsername,
    required this.hasPassword,
    required this.isAdmin,
  });

  final int id;
  final String? login;
  final String displayName;
  final int? tgId;
  final String? tgUsername;
  final bool hasPassword;
  final bool isAdmin;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      login: json['login'] as String?,
      displayName: json['name'] as String? ?? json['login'] as String? ?? 'Аккаунт',
      tgId: (json['tg_id'] as num?)?.toInt(),
      tgUsername: json['tg_username'] as String?,
      hasPassword: json['has_password'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }
}

class Profile {
  const Profile({
    required this.user,
    required this.plans,
    required this.extendOptions,
    required this.maxActive,
  });

  final AppUser user;
  final List<PlanInfo> plans;
  final List<int> extendOptions;
  final int? maxActive;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      user: AppUser.fromJson((json['user'] as Map<String, dynamic>?) ?? const {}),
      plans: ((json['plans'] as List?) ?? const [])
          .map((e) => PlanInfo.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      extendOptions: ((json['extend_options'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(growable: false),
      maxActive: ((json['limits'] as Map<String, dynamic>?) ?? const {})['max_active'] is num
          ? (((json['limits'] as Map<String, dynamic>)['max_active']) as num).toInt()
          : null,
    );
  }
}

class DeviceEntry {
  const DeviceEntry({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.createdAt,
    required this.lastSeenAt,
    required this.lastIp,
    required this.current,
  });

  final int id;
  final String deviceId;
  final String name;
  final String platform;
  final String? appVersion;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final String? lastIp;
  final bool current;

  factory DeviceEntry.fromJson(Map<String, dynamic> json) {
    DateTime at(String key) => DateTime.fromMillisecondsSinceEpoch(
          (((json[key] as num?)?.toDouble() ?? 0) * 1000).round(),
        );
    return DeviceEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      deviceId: json['device_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Устройство',
      platform: json['platform'] as String? ?? 'other',
      appVersion: json['app_version'] as String?,
      createdAt: at('created_at'),
      lastSeenAt: at('last_seen_at'),
      lastIp: json['last_ip'] as String?,
      current: json['current'] as bool? ?? false,
    );
  }
}

class TokenPair {
  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get expiringSoon => DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  factory TokenPair.fromJson(Map<String, dynamic> json) {
    final seconds = (json['expires_in'] as num?)?.toInt() ?? 900;
    return TokenPair(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      expiresAt: DateTime.now().add(Duration(seconds: seconds)),
    );
  }
}

class TelegramLogin {
  const TelegramLogin({
    required this.token,
    required this.nonce,
    required this.url,
    required this.expiresIn,
  });

  final String token;
  final String nonce;
  final String url;
  final int expiresIn;

  factory TelegramLogin.fromJson(Map<String, dynamic> json) {
    return TelegramLogin(
      token: json['token'] as String? ?? '',
      nonce: json['nonce'] as String? ?? '',
      url: json['url'] as String? ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 300,
    );
  }
}
