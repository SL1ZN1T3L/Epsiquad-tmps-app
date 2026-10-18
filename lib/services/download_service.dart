import 'dart:async';
import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../messenger.dart';

class DownloadFailure implements Exception {
  DownloadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class DownloadCanceled implements Exception {
  const DownloadCanceled();
}

/// Ссылка на запущенное скачивание, нужна для паузы, продолжения и отмены.
class DownloadHandle {
  DownloadHandle._(this._task);

  final DownloadTask _task;
}

class DownloadService {
  static bool _configured = false;
  static bool _tapRegistered = false;
  static const _savedKey = 'tmps.saved_downloads';
  static const _savedLimit = 60;
  static const _files = MethodChannel('com.epsiquad.tmps/files');
  static int? _sdk;

  /// Вызывается один раз при старте приложения, до runApp.
  ///
  /// Настраивает тексты уведомлений и вешает обработчик нажатия на
  /// уведомление «Сохранено в Загрузки», который открывает скачанный файл.
  /// Обработчик нужно регистрировать сразу при запуске: если приложение было
  /// закрыто, Android поднимет его по нажатию на уведомление.
  static void init() {
    _configure();
    if (_tapRegistered) return;
    _tapRegistered = true;
    FileDownloader().registerCallbacks(
      taskNotificationTapCallback: _onNotificationTap,
    );
  }

  static void _configure() {
    if (_configured) return;
    _configured = true;
    FileDownloader().configureNotification(
      running: const TaskNotification('{filename}', 'Скачивание, {progress}'),
      complete: const TaskNotification('{filename}', 'Сохранено в Загрузки. Нажмите, чтобы открыть'),
      error: const TaskNotification('{filename}', 'Не удалось скачать'),
      paused: const TaskNotification('{filename}', 'Скачивание на паузе'),
      progressBar: true,
    );
  }

  Future<bool> pause(DownloadHandle handle) async {
    try {
      return await FileDownloader().pause(handle._task);
    } catch (_) {
      return false;
    }
  }

  Future<bool> resume(DownloadHandle handle) async {
    try {
      return await FileDownloader().resume(handle._task);
    } catch (_) {
      return false;
    }
  }

  Future<void> cancel(DownloadHandle handle) async {
    try {
      await FileDownloader().cancelTaskWithId(handle._task.taskId);
    } catch (_) {}
  }

  Future<void> _askNotifications() => requestNotificationPermission();

  /// Просит разрешение на уведомления (Android 13+), если его ещё нет.
  static Future<void> requestNotificationPermission() async {
    try {
      final current = await FileDownloader().permissions.status(PermissionType.notifications);
      if (current != PermissionStatus.granted) {
        await FileDownloader().permissions.request(PermissionType.notifications);
      }
    } catch (_) {}
  }

  Future<String> save({
    required Uri url,
    required Map<String, String> headers,
    required String filename,
    void Function(double progress)? onProgress,
    void Function(DownloadHandle handle)? onStart,
    void Function(bool paused)? onPaused,
    void Function(bool supported)? onPauseSupport,
    bool allowPause = true,
  }) async {
    _configure();
    await _askNotifications();

    final task = DownloadTask(
      url: url.toString(),
      filename: filename,
      headers: headers,
      baseDirectory: BaseDirectory.applicationDocuments,
      directory: 'tmps',
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: allowPause,
      displayName: filename,
    );

    onStart?.call(DownloadHandle._(task));

    var askedPauseSupport = false;
    final result = await FileDownloader().download(
      task,
      onProgress: (value) {
        if (value >= 0 && onProgress != null) onProgress(value);
      },
      onStatus: (status) {
        if (status == TaskStatus.paused) {
          onPaused?.call(true);
        } else if (status == TaskStatus.running || status == TaskStatus.enqueued) {
          onPaused?.call(false);
        }
        // Как только задача реально стартовала, плагин знает, отдаёт ли сервер
        // Accept-Ranges. Без этого пауза и докачка невозможны.
        if (status == TaskStatus.running && allowPause && !askedPauseSupport) {
          askedPauseSupport = true;
          unawaited(_pauseSupport(task).then((ok) => onPauseSupport?.call(ok)));
        }
      },
    );

    if (result.status == TaskStatus.canceled) throw const DownloadCanceled();
    if (result.status != TaskStatus.complete) {
      throw DownloadFailure(_reason(result));
    }

    final saved = await FileDownloader().moveToSharedStorage(task, SharedStorage.downloads);
    if (saved == null) {
      throw DownloadFailure('Файл скачался, но не удалось положить его в «Загрузки»');
    }
    await _remember(task.taskId, saved);
    return saved;
  }

  Future<bool> _pauseSupport(DownloadTask task) async {
    try {
      return await FileDownloader()
          .taskCanResume(task)
          .timeout(const Duration(seconds: 20), onTimeout: () => true);
    } catch (_) {
      return true;
    }
  }

  String _reason(TaskStatusUpdate result) {
    switch (result.status) {
      case TaskStatus.notFound:
        return 'Файл уже удалён из хранилища';
      case TaskStatus.canceled:
        return 'Скачивание отменено';
      case TaskStatus.paused:
        return 'Скачивание на паузе';
      default:
        final code = result.responseStatusCode;
        if (code == 403) return 'Нет доступа к файлу, откройте хранилище заново';
        if (code == 410) return 'Срок хранилища истёк';
        return 'Не удалось скачать файл';
    }
  }

  // ---- Открытие скачанного файла ----

  /// Путь сохранённого файла хранится на диске по taskId: уведомление может
  /// быть нажато уже после перезапуска приложения.
  static Future<void> _remember(String taskId, String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _readSaved(prefs);
      map.remove(taskId);
      map[taskId] = path;
      while (map.length > _savedLimit) {
        map.remove(map.keys.first);
      }
      await prefs.setString(_savedKey, jsonEncode(map));
    } catch (_) {}
  }

  static Map<String, String> _readSaved(SharedPreferences prefs) {
    final raw = prefs.getString(_savedKey);
    final result = <String, String>{};
    if (raw == null) return result;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is String) result[key] = value;
        });
      }
    } catch (_) {}
    return result;
  }

  static Future<String?> _recall(String taskId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return _readSaved(prefs)[taskId];
    } catch (_) {
      return null;
    }
  }

  static Future<int> _sdkInt() async {
    final known = _sdk;
    if (known != null) return known;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _sdk = info.version.sdkInt;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _onNotificationTap(Task task, NotificationType type) async {
    if (type != NotificationType.complete) return;
    // На Android 10 и новее тап обрабатывает MainActivity (MediaStore и выбор
    // приложения), здесь остаётся запасной путь для Android 8 и 9.
    if (await _sdkInt() >= 29) return;
    // Уведомление появляется сразу после загрузки, а файл переносится в
    // «Загрузки» чуть позже, поэтому путь может появиться с небольшой задержкой.
    String? path;
    for (var attempt = 0; attempt < 10 && path == null; attempt++) {
      path = await _recall(task.taskId);
      if (path == null) await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (path == null) {
      showAppToast('Не удалось найти скачанный файл, откройте его из «Загрузок»');
      return;
    }
    await openSaved(path);
  }

  /// Открывает файл из «Загрузок» в подходящем приложении.
  static Future<bool> openSaved(String path) async {
    try {
      final name = path.split('/').last;
      final ok = await _files.invokeMethod<bool>('openDownload', {'name': name});
      if (ok == true) return true;
    } catch (_) {}
    try {
      final opened = await FileDownloader().openFile(filePath: path);
      if (!opened) {
        showAppToast('Не удалось открыть файл: нет подходящего приложения или файл удалён');
      }
      return opened;
    } catch (_) {
      showAppToast('Не удалось открыть файл');
      return false;
    }
  }
}
