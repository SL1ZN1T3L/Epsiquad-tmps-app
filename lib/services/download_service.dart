import 'package:background_downloader/background_downloader.dart';

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

  void _configure() {
    if (_configured) return;
    _configured = true;
    FileDownloader().configureNotification(
      running: const TaskNotification('{filename}', 'Скачивание, {progress}'),
      complete: const TaskNotification('{filename}', 'Сохранено в Загрузки'),
      error: const TaskNotification('{filename}', 'Не удалось скачать'),
      paused: const TaskNotification('{filename}', 'Скачивание на паузе'),
      progressBar: true,
    );
  }

  Future<void> _askNotifications() async {
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
    return saved;
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
}
