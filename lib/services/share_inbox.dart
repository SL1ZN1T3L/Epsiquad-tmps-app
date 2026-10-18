import 'package:flutter/services.dart';

/// Файл, который прислали из другого приложения через «Поделиться».
/// Нативная часть уже скопировала его в кэш приложения, поэтому [path]
/// можно читать обычным File.
class SharedFile {
  const SharedFile({required this.name, required this.size, required this.path});

  final String name;
  final int size;
  final String path;
}

class ShareInbox {
  static const _channel = MethodChannel('com.epsiquad.tmps/share');
  static bool _started = false;

  /// Подписывается на входящие файлы. Файлы, которые пришли до запуска
  /// Dart (приложение открыли через «Поделиться»), забираются сразу.
  static Future<void> start(void Function(List<SharedFile> files) onShared) async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') onShared(_parse(call.arguments));
      return null;
    });
    try {
      final initial = await _channel.invokeMethod<List<Object?>>('takeShared');
      final files = _parse(initial);
      if (files.isNotEmpty) onShared(files);
    } catch (_) {}
  }

  static List<SharedFile> _parse(Object? raw) {
    if (raw is! List) return const [];
    final files = <SharedFile>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final name = entry['name'];
      final path = entry['path'];
      final size = entry['size'];
      if (name is String && path is String && size is num) {
        files.add(SharedFile(name: name, size: size.toInt(), path: path));
      }
    }
    return files;
  }
}
