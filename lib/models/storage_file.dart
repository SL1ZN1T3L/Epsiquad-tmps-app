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

/// Тип файла по расширению: нужен, когда сервер не видит настоящего имени (зашифрованные хранилища).
String kindForName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic', 'heif', 'avif'};
  const videos = {'mp4', 'm4v', 'mov', 'webm', 'mkv', '3gp', 'avi'};
  const audios = {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'oga', 'opus', 'amr'};
  const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz'};
  const texts = {'txt', 'md', 'log', 'csv', 'tsv', 'rtf'};
  const codes = {
    'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'html', 'htm', 'css', 'js', 'ts', 'py', 'kt',
    'java', 'c', 'h', 'cpp', 'cs', 'go', 'rs', 'rb', 'php', 'sh', 'sql', 'dart',
  };
  if (images.contains(ext)) return 'image';
  if (videos.contains(ext)) return 'video';
  if (audios.contains(ext)) return 'audio';
  if (ext == 'pdf') return 'pdf';
  if (archives.contains(ext)) return 'archive';
  if (texts.contains(ext)) return 'text';
  if (codes.contains(ext)) return 'code';
  return 'other';
}

class StorageFile {
  const StorageFile({
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.mime,
    required this.kind,
    this.displayName,
    this.chunkSize,
    this.plainSize,
  });

  /// Имя файла на сервере. В зашифрованном хранилище это токен `e2e1.…`.
  final String name;
  final int size;
  final DateTime modifiedAt;
  final String mime;
  final String kind;

  /// Расшифрованное имя (только для E2EE-хранилищ).
  final String? displayName;

  /// Размер куска, с которым зашифрован файл (из токена имени).
  final int? chunkSize;

  /// Размер файла без служебных байт шифрования.
  final int? plainSize;

  /// Имя для показа пользователю.
  String get title => displayName ?? name;

  /// Размер для показа пользователю.
  int get shownSize => plainSize ?? size;

  StorageFile copyWith({String? displayName, int? chunkSize, int? plainSize, String? kind}) {
    return StorageFile(
      name: name,
      size: size,
      modifiedAt: modifiedAt,
      mime: mime,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      chunkSize: chunkSize ?? this.chunkSize,
      plainSize: plainSize ?? this.plainSize,
    );
  }

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
    this.e2ee = false,
    this.e2eeCheck,
  });

  final String role;
  final bool canWrite;
  final List<StorageFile> files;
  final int usedBytes;
  final int quotaBytes;
  final int chunkSize;
  final bool expired;
  final Map<String, FileStats> stats;

  /// Хранилище зашифровано, [e2eeCheck] - проверочная запись для сверки ключа.
  final bool e2ee;
  final String? e2eeCheck;

  StorageState withFiles(List<StorageFile> next) {
    return StorageState(
      role: role,
      canWrite: canWrite,
      files: next,
      usedBytes: usedBytes,
      quotaBytes: quotaBytes,
      chunkSize: chunkSize,
      expired: expired,
      stats: stats,
      e2ee: e2ee,
      e2eeCheck: e2eeCheck,
    );
  }

  bool get isOwner => role == 'owner';
  int get freeBytes => quotaBytes - usedBytes < 0 ? 0 : quotaBytes - usedBytes;

  factory StorageState.fromJson(Map<String, dynamic> json) {
    final usage = (json['usage'] as Map<String, dynamic>?) ?? const {};
    final rawStats = (json['stats'] as Map<String, dynamic>?) ?? const {};
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
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
      e2ee: meta['e2ee'] as bool? ?? false,
      e2eeCheck: meta['e2ee_check'] as String?,
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
