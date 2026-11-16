import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../messenger.dart';
import 'e2ee.dart';
import 'secure_store.dart';

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

class DownloadObserver {
  const DownloadObserver({
    this.onPhase,
    this.onProgress,
    this.onStart,
    this.onPaused,
    this.onSaved,
    this.onError,
    this.onCanceled,
  });

  final void Function(String? hint)? onPhase;
  final void Function(double progress)? onProgress;
  final void Function(DownloadHandle handle)? onStart;
  final void Function(bool paused)? onPaused;
  final void Function(String path)? onSaved;
  final void Function(String message)? onError;
  final void Function()? onCanceled;
}

class DownloadSnapshot {
  const DownloadSnapshot({
    required this.id,
    required this.name,
    required this.allowPause,
    required this.archive,
    required this.progress,
    this.cipherName,
    this.decrypt,
    this.handle,
    this.paused = false,
    this.canceled = false,
    this.savedPath,
    this.error,
  });

  final String id;
  final String name;
  final String? cipherName;
  final E2eeDownload? decrypt;
  final bool allowPause;
  final bool archive;
  final DownloadHandle? handle;
  final double progress;
  final bool paused;
  final bool canceled;
  final String? savedPath;
  final String? error;
}

class DownloadService {
  static bool _configured = false;
  static bool _callbacksRegistered = false;
  static Future<void>? _startFuture;
  static final _secure = SecureStore();
  static final _observers = <String, DownloadObserver>{};
  static final _postprocessing = <String, Future<String>>{};
  static final _activeRecords = <String, Map<String, dynamic>>{};
  static final _activeDecrypt = <String, E2eeDownload>{};
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
  static Future<void> init() {
    _configure();
    if (!_callbacksRegistered) {
      _callbacksRegistered = true;
      FileDownloader().registerCallbacks(
        taskStatusCallback: _onStatus,
        taskProgressCallback: _onProgress,
        taskNotificationTapCallback: _onNotificationTap,
      );
    }
    // start() включает персистентное отслеживание и возвращает нативные задачи
    // после process death. Регистрация callbacks выше обязана быть раньше.
    final existing = _startFuture;
    if (existing != null) return existing;
    late final Future<void> start;
    start = FileDownloader()
        .start(
      doTrackTasks: true,
      markDownloadedComplete: true,
      doRescheduleKilledTasks: true,
      autoCleanDatabase: true,
    )
        .catchError((_) {
      // Ошибка инициализации плагина не должна блокировать запуск приложения.
      if (identical(_startFuture, start)) _startFuture = null;
    });
    return _startFuture = start;
  }

  static void _configure() {
    if (_configured) return;
    _configured = true;
    FileDownloader().configureNotification(
      running:
          const TaskNotification('{displayName}', 'Скачивание, {progress}'),
      complete: const TaskNotification(
          '{displayName}', 'Сохранено в Загрузки. Нажмите, чтобы открыть'),
      error: const TaskNotification('{displayName}', 'Не удалось скачать'),
      paused: const TaskNotification('{displayName}', 'Скачивание на паузе'),
      progressBar: true,
    );
  }

  static Future<void> cancelAll() async {
    try {
      final records = await _secure.readDownloadRecords();
      final ids = records
          .map((record) => record['taskId'])
          .whereType<String>()
          .toList(growable: false);
      // На PIN wipe защищённые metadata уже удалены, поэтому отменяем и всю
      // нативную группу, а не только задачи, найденные по записям.
      await FileDownloader().cancelAll();
      if (ids.isNotEmpty) await FileDownloader().cancelTasksWithIds(ids);
    } catch (_) {}
  }

  static Future<void> cancelStorage(String storageCode) async {
    try {
      final records = await _secure.readDownloadRecords();
      final ids = records
          .where((record) => record['storageCode'] == storageCode)
          .map((record) => record['taskId'])
          .whereType<String>()
          .toList(growable: false);
      if (ids.isNotEmpty) await FileDownloader().cancelTasksWithIds(ids);
    } catch (_) {}
  }

  void observe(String taskId, DownloadObserver observer) {
    _observers[taskId] = observer;
  }

  void unobserve(String taskId) {
    _observers.remove(taskId);
  }

  Future<void> forget(String taskId) async {
    unobserve(taskId);
    try {
      await _secure.deleteDownloadRecord(taskId);
    } catch (_) {}
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
      final current = await FileDownloader()
          .permissions
          .status(PermissionType.notifications);
      if (current != PermissionStatus.granted) {
        await FileDownloader()
            .permissions
            .request(PermissionType.notifications);
      }
    } catch (_) {}
  }

  Future<String> save({
    required String taskId,
    required String storageCode,
    required Uri url,
    required Map<String, String> headers,
    required String filename,
    String? displayName,
    bool archive = false,
    E2eeDownload? decrypt,
    void Function(String? hint)? onPhase,
    void Function(double progress)? onProgress,
    void Function(DownloadHandle handle)? onStart,
    void Function(bool paused)? onPaused,
    void Function(bool supported)? onPauseSupport,
    bool allowPause = true,
  }) async {
    await init();
    await _askNotifications();

    final task = DownloadTask(
      taskId: taskId,
      url: url.toString(),
      filename: filename,
      headers: headers,
      baseDirectory: BaseDirectory.applicationDocuments,
      directory: 'tmps',
      updates: Updates.statusAndProgress,
      retries: 3,
      allowPause: allowPause,
      displayName: displayName ?? filename,
    );

    final record = <String, dynamic>{
      'taskId': taskId,
      'storageCode': storageCode,
      'displayName': displayName ?? filename,
      'cipherName': decrypt == null ? null : filename,
      'allowPause': allowPause,
      'archive': archive,
      'fileId': decrypt?.fileId,
      'chunkSize': decrypt?.chunkSize,
      'saveAs': decrypt?.saveAs,
    };
    // Запись должна существовать до запуска нативной задачи: процесс могут
    // завершить сразу после enqueue, ещё до первого callback.
    await _secure.writeDownloadRecord(taskId, record);
    onStart?.call(DownloadHandle._(task));

    _activeRecords[taskId] = record;
    if (decrypt != null) _activeDecrypt[taskId] = decrypt;
    try {
      var askedPauseSupport = false;
      final result = await FileDownloader().download(
        task,
        onProgress: (value) {
          if (value >= 0 && onProgress != null) onProgress(value);
        },
        onStatus: (status) {
          if (status == TaskStatus.paused) {
            onPaused?.call(true);
          } else if (status == TaskStatus.running ||
              status == TaskStatus.enqueued) {
            onPaused?.call(false);
          }
          // Как только задача реально стартовала, плагин знает, отдаёт ли сервер
          // Accept-Ranges. Без этого пауза и докачка невозможны.
          if (status == TaskStatus.running &&
              allowPause &&
              !askedPauseSupport) {
            askedPauseSupport = true;
            unawaited(
                _pauseSupport(task).then((ok) => onPauseSupport?.call(ok)));
          }
        },
      );

      if (result.status == TaskStatus.canceled) {
        throw const DownloadCanceled();
      }
      if (result.status != TaskStatus.complete) {
        throw DownloadFailure(_reason(result));
      }

      onPhase?.call(decrypt == null ? null : 'Расшифровываю…');
      try {
        return await _postprocess(task, record: record, decrypt: decrypt);
      } finally {
        onPhase?.call(null);
      }
    } finally {
      _activeRecords.remove(taskId);
      _activeDecrypt.remove(taskId);
    }
  }

  /// Постобработка общая для обычного await и восстановленной нативной задачи.
  /// Внутри одного процесса повторный complete не запускает второй перенос или
  /// расшифровку; метаданные удаляются только после сохранения результата.
  static Future<String> _postprocess(
    DownloadTask task, {
    Map<String, dynamic>? record,
    E2eeDownload? decrypt,
  }) {
    final running = _postprocessing[task.taskId];
    if (running != null) return running;
    final future = _finish(task, record: record, decrypt: decrypt);
    _postprocessing[task.taskId] = future;
    void cleanup() {
      if (identical(_postprocessing[task.taskId], future)) {
        _postprocessing.remove(task.taskId);
      }
    }

    unawaited(future.then((_) => cleanup(), onError: (_) => cleanup()));
    return future;
  }

  static Future<String> _finish(
    DownloadTask task, {
    Map<String, dynamic>? record,
    E2eeDownload? decrypt,
  }) async {
    // complete может прийти одновременно через глобальный callback и через
    // await download(). Если перенос уже завершён, возвращаем его результат,
    // а не создаём вторую копию в «Загрузках».
    final previous = await _recall(task.taskId);
    if (previous != null) {
      try {
        await _secure.deleteDownloadRecord(task.taskId);
      } catch (_) {}
      return previous;
    }
    final metadata = record ?? await _secure.readDownloadRecord(task.taskId);
    if (metadata == null) {
      throw DownloadFailure('Метаданные скачивания удалены, повторите его');
    }
    final fileId = metadata['fileId'];
    final chunkSize = metadata['chunkSize'];
    final saveAs = metadata['saveAs'];
    if (decrypt == null &&
        fileId is String &&
        chunkSize is num &&
        saveAs is String) {
      final keyText =
          await _secure.readE2eeKey(metadata['storageCode'] as String? ?? '');
      if (keyText == null) {
        throw DownloadFailure(
            'Файл скачан, но для расшифровки нужен ключ E2EE');
      }
      decrypt = E2eeDownload(
        key: E2ee.keyBytes(keyText),
        fileId: fileId,
        chunkSize: chunkSize.toInt(),
        saveAs: saveAs,
      );
    }

    final String? saved;
    if (decrypt == null) {
      saved = await FileDownloader()
          .moveToSharedStorage(task, SharedStorage.downloads);
    } else {
      try {
        saved = await _decryptToDownloads(task, decrypt);
      } on E2eeException catch (e) {
        throw DownloadFailure(e.message);
      }
    }
    if (saved == null) {
      throw DownloadFailure(
          'Файл скачался, но не удалось положить его в «Загрузки»');
    }
    await _remember(task.taskId, saved);
    try {
      await _secure.deleteDownloadRecord(task.taskId);
    } catch (_) {
      // Путь уже записан: повторный complete вернёт его через _recall и не
      // создаст дубликат, даже если удаление metadata временно не удалось.
    }
    return saved;
  }

  static void _onStatus(TaskStatusUpdate update) {
    final rawTask = update.task;
    if (rawTask is! DownloadTask) return;
    final task = rawTask;
    final observer = _observers[task.taskId];
    if (observer != null) {
      observer.onStart?.call(DownloadHandle._(task));
      switch (update.status) {
        case TaskStatus.paused:
          observer.onPaused?.call(true);
          break;
        case TaskStatus.enqueued:
        case TaskStatus.running:
        case TaskStatus.waitingToRetry:
          observer.onPaused?.call(false);
          break;
        case TaskStatus.canceled:
          observer.onCanceled?.call();
          break;
        case TaskStatus.complete:
          break;
        default:
          observer.onError?.call(_reason(update));
          break;
      }
    }
    if (update.status != TaskStatus.complete) return;
    unawaited(() async {
      observer?.onPhase?.call('Сохраняю…');
      try {
        final saved = await _postprocess(task);
        observer?.onSaved?.call(saved);
      } on DownloadFailure catch (e) {
        observer?.onError?.call(e.message);
      } catch (_) {
        observer?.onError?.call('Файл скачан, но не удалось сохранить его');
      } finally {
        observer?.onPhase?.call(null);
      }
    }());
  }

  static void _onProgress(TaskProgressUpdate update) {
    if (update.progress >= 0) {
      _observers[update.task.taskId]?.onProgress?.call(update.progress);
    }
  }

  /// Повторно читает статус после привязки UI, закрывая окно гонки между
  /// восстановлением списка и регистрацией observer.
  Future<void> refresh(String taskId) async {
    try {
      final record = await FileDownloader().database.recordForId(taskId);
      if (record == null) return;
      if (record.progress >= 0) {
        _observers[taskId]?.onProgress?.call(record.progress);
      }
      _onStatus(TaskStatusUpdate(record.task, record.status, record.exception));
    } catch (_) {}
  }

  Future<List<DownloadSnapshot>> restoreForStorage(String storageCode) async {
    await init();
    List<Map<String, dynamic>> records;
    try {
      records = await _secure.readDownloadRecords();
    } catch (_) {
      return const [];
    }
    final selected = records.where((r) => r['storageCode'] == storageCode);
    if (selected.isEmpty) return const [];

    final databaseRecords = await FileDownloader().database.allRecords();
    final byId = {for (final record in databaseRecords) record.taskId: record};
    final result = <DownloadSnapshot>[];
    for (final metadata in selected) {
      final taskId = metadata['taskId'];
      if (taskId is! String) continue;
      final stored = byId[taskId];
      final rawTask = stored?.task ?? await FileDownloader().taskForId(taskId);
      final task = rawTask is DownloadTask ? rawTask : null;
      final name =
          metadata['displayName'] as String? ?? task?.filename ?? 'file';
      final allowPause = metadata['allowPause'] != false;
      final archive = metadata['archive'] == true;
      final cipherName = metadata['cipherName'] as String?;
      E2eeDownload? decrypt;
      final fileId = metadata['fileId'];
      final chunkSize = metadata['chunkSize'];
      final saveAs = metadata['saveAs'];
      if (fileId is String && chunkSize is num && saveAs is String) {
        try {
          final key = await _secure.readE2eeKey(storageCode);
          if (key != null) {
            decrypt = E2eeDownload(
              key: E2ee.keyBytes(key),
              fileId: fileId,
              chunkSize: chunkSize.toInt(),
              saveAs: saveAs,
            );
          }
        } catch (_) {}
      }

      if (stored == null && task == null) {
        final saved = await _recall(taskId);
        result.add(DownloadSnapshot(
          id: taskId,
          name: name,
          cipherName: cipherName,
          decrypt: decrypt,
          allowPause: allowPause,
          archive: archive,
          progress: saved == null ? 0 : 1,
          savedPath: saved,
          error: saved == null
              ? 'Нативная задача не найдена. Повторите скачивание'
              : null,
        ));
        continue;
      }

      final status = stored?.status ?? TaskStatus.running;
      final progress =
          stored != null && stored.progress >= 0 ? stored.progress : 0.0;
      String? saved;
      String? error;
      final canceled = status == TaskStatus.canceled;
      if (status == TaskStatus.complete && task != null) {
        try {
          saved = await _postprocess(task, record: metadata, decrypt: decrypt);
        } on DownloadFailure catch (e) {
          error = e.message;
        } catch (_) {
          error = 'Файл скачан, но не удалось сохранить его';
        }
      } else if (status.isFinalState && !canceled) {
        error = _reason(TaskStatusUpdate(task!, status, stored?.exception));
      }
      result.add(DownloadSnapshot(
        id: taskId,
        name: name,
        cipherName: cipherName,
        decrypt: decrypt,
        allowPause: allowPause,
        archive: archive,
        handle: task == null ? null : DownloadHandle._(task),
        progress: saved == null ? progress : 1,
        paused: status == TaskStatus.paused,
        canceled: canceled,
        savedPath: saved,
        error: error,
      ));
    }
    return result;
  }

  static Future<String?> _decryptToDownloads(
      DownloadTask task, E2eeDownload decrypt) async {
    final cipherPath = await task.filePath();
    final plainPath =
        '${File(cipherPath).parent.path}/${_safeFileName(decrypt.saveAs)}';
    await E2ee.decryptFile(
      source: cipherPath,
      target: plainPath,
      key: decrypt.key,
      fileId: decrypt.fileId,
      chunkSize: decrypt.chunkSize,
    );
    final saved = await FileDownloader()
        .moveFileToSharedStorage(plainPath, SharedStorage.downloads);
    // Шифртекст нужен для повторной постобработки, если перенос не удался или
    // процесс завершили между расшифровкой и сохранением.
    if (saved != null) {
      try {
        final cipher = File(cipherPath);
        if (await cipher.exists()) await cipher.delete();
      } catch (_) {}
    }
    return saved;
  }

  static String _safeFileName(String name) {
    var safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    if (safe.length > 120) {
      final dot = safe.lastIndexOf('.');
      final ext = dot > 0 && safe.length - dot <= 12 ? safe.substring(dot) : '';
      safe = safe.substring(0, 120 - ext.length) + ext;
    }
    return safe.isEmpty ? 'file' : safe;
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

  static String _reason(TaskStatusUpdate result) {
    switch (result.status) {
      case TaskStatus.notFound:
        return 'Файл уже удалён из хранилища';
      case TaskStatus.canceled:
        return 'Скачивание отменено';
      case TaskStatus.paused:
        return 'Скачивание на паузе';
      default:
        final code = result.responseStatusCode;
        if (code == 403) {
          return 'Нет доступа к файлу, откройте хранилище заново';
        }
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

  static Future<void> _onNotificationTap(
      Task task, NotificationType type) async {
    if (type != NotificationType.complete) return;
    // На Android 10 и новее тап обрабатывает MainActivity (MediaStore и выбор
    // приложения), здесь остаётся запасной путь для Android 8 и 9.
    if (await _sdkInt() >= 29) return;
    // Уведомление появляется сразу после загрузки, а файл переносится в
    // «Загрузки» чуть позже, поэтому путь может появиться с небольшой задержкой.
    String? path;
    for (var attempt = 0; attempt < 10 && path == null; attempt++) {
      path = await _recall(task.taskId);
      if (path == null) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (path == null) {
      showAppToast(
          'Не удалось найти скачанный файл, откройте его из «Загрузок»');
      return;
    }
    await openSaved(path);
  }

  /// Открывает файл из «Загрузок» в подходящем приложении.
  static Future<bool> openSaved(String path) async {
    try {
      final name = path.split('/').last;
      final ok =
          await _files.invokeMethod<bool>('openDownload', {'name': name});
      if (ok == true) return true;
    } catch (_) {}
    try {
      final opened = await FileDownloader().openFile(filePath: path);
      if (!opened) {
        showAppToast(
            'Не удалось открыть файл: нет подходящего приложения или файл удалён');
      }
      return opened;
    } catch (_) {
      showAppToast('Не удалось открыть файл');
      return false;
    }
  }
}
