class FileStats {
  const FileStats({required this.views, required this.downloads});

  final int views;
  final int downloads;

  factory FileStats.fromJson(Map<String, dynamic> json) {
    return FileStats(
      views: (json['views'] as num?)?.toInt() ?? 0,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
    );
  }
}

class StorageFile {
  const StorageFile({
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.mime,
    required this.kind,
  });

  final String name;
  final int size;
  final DateTime modifiedAt;
  final String mime;
  final String kind;

  factory StorageFile.fromJson(Map<String, dynamic> json) {
    return StorageFile(
      name: json['name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        (((json['mtime'] as num?)?.toDouble() ?? 0) * 1000).round(),
      ),
      mime: json['mime'] as String? ?? 'application/octet-stream',
      kind: json['kind'] as String? ?? 'other',
    );
  }
}

class StorageState {
  const StorageState({
    required this.role,
    required this.canWrite,
    required this.files,
    required this.usedBytes,
    required this.quotaBytes,
    required this.chunkSize,
    required this.expired,
    required this.stats,
  });

  final String role;
  final bool canWrite;
  final List<StorageFile> files;
  final int usedBytes;
  final int quotaBytes;
  final int chunkSize;
  final bool expired;
  final Map<String, FileStats> stats;

  bool get isOwner => role == 'owner';
  int get freeBytes => quotaBytes - usedBytes < 0 ? 0 : quotaBytes - usedBytes;

  factory StorageState.fromJson(Map<String, dynamic> json) {
    final usage = (json['usage'] as Map<String, dynamic>?) ?? const {};
    final rawStats = (json['stats'] as Map<String, dynamic>?) ?? const {};
    return StorageState(
      role: json['role'] as String? ?? 'guest',
      canWrite: json['can_write'] as bool? ?? false,
      files: ((json['files'] as List?) ?? const [])
          .map((e) => StorageFile.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      usedBytes: (usage['used_bytes'] as num?)?.toInt() ?? 0,
      quotaBytes: (usage['quota_bytes'] as num?)?.toInt() ?? 0,
      chunkSize: (json['chunk_size'] as num?)?.toInt() ?? 8 * 1024 * 1024,
      expired: json['expired'] as bool? ?? false,
      stats: rawStats.map(
        (key, value) => MapEntry(key, FileStats.fromJson(value as Map<String, dynamic>)),
      ),
    );
  }
}

class UploadSession {
  const UploadSession({
    required this.uid,
    required this.name,
    required this.chunkSize,
    required this.totalChunks,
    required this.received,
  });

  final String uid;
  final String name;
  final int chunkSize;
  final int totalChunks;
  final Set<int> received;

  factory UploadSession.fromJson(Map<String, dynamic> json) {
    return UploadSession(
      uid: json['uid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      chunkSize: (json['chunk_size'] as num?)?.toInt() ?? 8 * 1024 * 1024,
      totalChunks: (json['total_chunks'] as num?)?.toInt() ?? 0,
      received: ((json['received'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toSet(),
    );
  }
}
