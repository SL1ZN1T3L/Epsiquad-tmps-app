class PlanInfo {
  const PlanInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.quotaBytes,
    required this.ttlOptions,
    required this.maxLifetimeHours,
    required this.extendable,
    required this.unlimited,
    required this.adminOnly,
  });

  final String id;
  final String name;
  final String description;
  final int quotaBytes;
  final List<int> ttlOptions;
  final int? maxLifetimeHours;
  final bool extendable;
  final bool unlimited;
  final bool adminOnly;

  factory PlanInfo.fromJson(Map<String, dynamic> json) {
    return PlanInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      quotaBytes: (json['quota_bytes'] as num?)?.toInt() ?? 0,
      ttlOptions: ((json['ttl_options'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(growable: false),
      maxLifetimeHours: (json['max_lifetime_hours'] as num?)?.toInt(),
      extendable: json['extendable'] as bool? ?? false,
      unlimited: json['unlimited'] as bool? ?? false,
      adminOnly: json['admin_only'] as bool? ?? false,
    );
  }
}

class UploadRules {
  const UploadRules({
    required this.chunkBytes,
    required this.parallel,
    required this.resumable,
  });

  final int chunkBytes;
  final int parallel;
  final bool resumable;

  factory UploadRules.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return UploadRules(
      chunkBytes: (data['chunk_bytes'] as num?)?.toInt() ?? 8 * 1024 * 1024,
      parallel: (data['parallel'] as num?)?.toInt() ?? 3,
      resumable: data['resumable'] as bool? ?? true,
    );
  }
}

class ServerConfig {
  const ServerConfig({
    required this.apiVersion,
    required this.serverVersion,
    required this.minAppVersion,
    required this.publicUrl,
    required this.botUsername,
    required this.repoUrl,
    required this.plans,
    required this.extendOptions,
    required this.userMaxActive,
    required this.upload,
    required this.accessModes,
  });

  final int apiVersion;
  final String serverVersion;
  final String minAppVersion;
  final String publicUrl;
  final String? botUsername;
  final String? repoUrl;
  final List<PlanInfo> plans;
  final List<int> extendOptions;
  final int userMaxActive;
  final UploadRules upload;
  final List<String> accessModes;

  bool get telegramAvailable => (botUsername ?? '').isNotEmpty;

  ServerConfig withPlans(List<PlanInfo> next, {List<int>? extend, int? maxActive}) {
    if (next.isEmpty) return this;
    return ServerConfig(
      apiVersion: apiVersion,
      serverVersion: serverVersion,
      minAppVersion: minAppVersion,
      publicUrl: publicUrl,
      botUsername: botUsername,
      repoUrl: repoUrl,
      plans: next,
      extendOptions: (extend == null || extend.isEmpty) ? extendOptions : extend,
      userMaxActive: maxActive ?? userMaxActive,
      upload: upload,
      accessModes: accessModes,
    );
  }

  PlanInfo? planById(String id) {
    for (final plan in plans) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      apiVersion: (json['api_version'] as num?)?.toInt() ?? 1,
      serverVersion: json['server_version'] as String? ?? '',
      minAppVersion: json['min_app_version'] as String? ?? '0.0.0',
      publicUrl: json['public_url'] as String? ?? '',
      botUsername: json['bot_username'] as String?,
      repoUrl: json['repo_url'] as String?,
      plans: ((json['plans'] as List?) ?? const [])
          .map((e) => PlanInfo.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      extendOptions: ((json['extend_options'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(growable: false),
      userMaxActive: (json['user_max_active'] as num?)?.toInt() ?? 3,
      upload: UploadRules.fromJson(json['upload'] as Map<String, dynamic>?),
      accessModes: ((json['access_modes'] as List?) ?? const ['public', 'readonly', 'private'])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }
}
