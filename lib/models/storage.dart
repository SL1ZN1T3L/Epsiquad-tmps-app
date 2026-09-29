DateTime? _at(Object? value) {
  if (value == null) return null;
  final seconds = (value as num).toDouble();
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
}

class PlanOption {
  const PlanOption({
    required this.plan,
    required this.planName,
    required this.description,
    required this.quotaBytes,
    required this.maxLifetimeHours,
    required this.extendable,
    required this.keepsTtl,
    required this.expiresAt,
    required this.direction,
    required this.available,
    required this.reason,
  });

  final String plan;
  final String planName;
  final String description;
  final int quotaBytes;
  final int? maxLifetimeHours;
  final bool extendable;
  final bool keepsTtl;
  final DateTime? expiresAt;
  final String direction;
  final bool available;
  final String? reason;

  bool get isUpgrade => direction == 'up';

  factory PlanOption.fromJson(Map<String, dynamic> json) {
    return PlanOption(
      plan: json['plan'] as String? ?? '',
      planName: json['plan_name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      quotaBytes: (json['quota_bytes'] as num?)?.toInt() ?? 0,
      maxLifetimeHours: (json['max_lifetime_hours'] as num?)?.toInt(),
      extendable: json['extendable'] as bool? ?? false,
      keepsTtl: json['keeps_ttl'] as bool? ?? false,
      expiresAt: _at(json['expires_at']),
      direction: json['direction'] as String? ?? 'up',
      available: json['available'] as bool? ?? false,
      reason: json['reason'] as String?,
    );
  }
}

class StorageItem {
  const StorageItem({
    required this.code,
    required this.url,
    required this.title,
    required this.plan,
    required this.planName,
    required this.quotaBytes,
    required this.usedBytes,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.expiresAt,
    required this.maxExpiresAt,
    required this.extendOptions,
    required this.extendRoomHours,
    required this.planOptions,
    required this.access,
  });

  final String code;
  final String url;
  final String? title;
  final String plan;
  final String planName;
  final int quotaBytes;
  final int usedBytes;
  final String status;
  final String source;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? maxExpiresAt;
  final List<int> extendOptions;
  final double extendRoomHours;
  final List<PlanOption> planOptions;
  final String access;

  String get displayTitle => (title ?? '').isNotEmpty ? title! : 'Хранилище $code';
  int get freeBytes => quotaBytes - usedBytes < 0 ? 0 : quotaBytes - usedBytes;
  double get usedRatio => quotaBytes <= 0 ? 0 : (usedBytes / quotaBytes).clamp(0.0, 1.0).toDouble();
  bool get unlimited => expiresAt == null;
  bool get canExtend => extendOptions.isNotEmpty;

  Duration? get timeLeft {
    final at = expiresAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  factory StorageItem.fromJson(Map<String, dynamic> json) {
    return StorageItem(
      code: json['code'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String?,
      plan: json['plan'] as String? ?? '',
      planName: json['plan_name'] as String? ?? '',
      quotaBytes: (json['quota_bytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'active',
      source: json['source'] as String? ?? 'app',
      createdAt: _at(json['created_at']),
      expiresAt: _at(json['expires_at']),
      maxExpiresAt: _at(json['max_expires_at']),
      extendOptions: ((json['extend_options'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(growable: false),
      extendRoomHours: (json['extend_room_hours'] as num?)?.toDouble() ?? 0,
      planOptions: ((json['plan_options'] as List?) ?? const [])
          .map((e) => PlanOption.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      access: json['access'] as String? ?? 'public',
    );
  }
}

class OwnerGrant {
  const OwnerGrant({
    required this.token,
    required this.header,
    required this.baseUrl,
    required this.expiresAt,
  });

  final String token;
  final String header;
  final String baseUrl;
  final DateTime expiresAt;

  bool get stale => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  factory OwnerGrant.fromJson(Map<String, dynamic> json) {
    final seconds = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return OwnerGrant(
      token: json['token'] as String? ?? '',
      header: json['header'] as String? ?? 'X-Tmps-Owner',
      baseUrl: json['base_url'] as String? ?? '',
      expiresAt: DateTime.now().add(Duration(seconds: seconds)),
    );
  }
}
