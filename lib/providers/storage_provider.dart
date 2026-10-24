import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show RequestAbortedException;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/storage.dart';
import '../models/storage_file.dart';
import '../services/api_client.dart';
import '../services/download_service.dart';
import '../services/e2ee.dart';
import '../services/node_service.dart';
import '../services/secure_store.dart';
import '../services/storage_service.dart';

enum UploadStatus { queued, uploading, paused, done, error, canceled }

class UploadSource {
  const UploadSource({
    required this.name,
    required this.size,
    required this.path,
    required this.openStream,
  });

  final String name;
  final int size;
  final String? path;
  final Stream<List<int>> Function() openStream;
}

class _ChunkReader {
  _ChunkReader(this._source);

  final UploadSource _source;
  RandomAccessFile? _handle;
  StreamIterator<List<int>>? _stream;
  Uint8List _carry = Uint8List(0);
  int _position = 0;

  Future<void> open() async {
    final path = _source.path;
    if (path != null && await File(path).exists()) {
      _handle = await File(path).open();
      return;
    }
    _stream = StreamIterator(_source.openStream());
  }

  Future<List<int>> read(int offset, int length) async {
    final handle = _handle;
    if (handle != null) {
      await handle.setPosition(offset);
      return handle.read(length);
    }
    if (offset < _position) {
      throw ApiException('Этот файл можно отправлять только по порядку');
    }
    while (_position < offset) {
      final skipped = await _take(offset - _position);
      if (skipped.isEmpty) break;
      _position += skipped.length;
    }
    final bytes = await _take(length);
    _position += bytes.length;
    return bytes;
  }

  Future<Uint8List> _take(int count) async {
    final iterator = _stream;
    if (iterator == null) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    while (builder.length < count) {
      if (_carry.isEmpty) {
        if (!await iterator.moveNext()) break;
        _carry = Uint8List.fromList(iterator.current);
      }
      final take = min(count - builder.length, _carry.length);
      builder.add(Uint8List.sublistView(_carry, 0, take));
      _carry = Uint8List.sublistView(_carry, take);
    }
    return builder.toBytes();
  }

  Future<void> close() async {
    await _handle?.close();
    await _stream?.cancel();
    _handle = null;
    _stream = null;
    _carry = Uint8List(0);
    _position = 0;
  }
}

/// Порядок файлов в списке хранилища.
enum FileSort {
  dateDesc('Сначала новые'),
  dateAsc('Сначала старые'),
  nameAsc('По имени, А-Я'),
  nameDesc('По имени, Я-А'),
  sizeDesc('Сначала большие'),
  sizeAsc('Сначала маленькие'),
  type('По типу');

  const FileSort(this.label);

  final String label;
}

class FileDownload {
  FileDownload({
    required this.id,
    required this.name,
    required this.build,
    required this.allowPause,
    this.cipherName,
    this.decrypt,
  });

  final String id;

  /// Имя для показа и для «Загрузок» (в зашифрованном хранилище - расшифрованное).
  final String name;

  /// Имя файла на сервере, если оно отличается от [name] (шифртекст до расшифровки).
  final String? cipherName;

  /// Не null - скачанный файл нужно расшифровать перед сохранением.
  final E2eeDownload? decrypt;

  /// Как заново собрать адрес скачивания при повторе.
  final Uri Function() build;
  final bool allowPause;

  double progress = 0;
  String? savedPath;
  String? error;
  String? hint;
  DownloadHandle? handle;
  bool canPause = true;

  /// null - пока неизвестно, true/false - ответ сервера (Accept-Ranges).
  bool? pauseSupported;
  bool paused = false;
  bool canceled = false;

  bool get pauseEnabled => canPause && pauseSupported != false;
  bool get done => savedPath != null;
  bool get running => savedPath == null && error == null && !canceled;
  bool get canRetry => !running && !done;
}

class UploadTask {
  UploadTask({required this.id, required this.source});

  final String id;
  final UploadSource source;

  String get name => source.name;
  int get size => source.size;

  UploadStatus status = UploadStatus.queued;
  int sentBytes = 0;
  String? uid;
  String? error;

  Completer<void> _abort = Completer<void>();

  /// Сигнал для текущего запроса: по нему отправка куска обрывается сразу.
  Future<void> get abortSignal => _abort.future;

  void armAbort() {
    if (_abort.isCompleted) _abort = Completer<void>();
  }

  void triggerAbort() {
    if (!_abort.isCompleted) _abort.complete();
  }

  double get progress => size <= 0 ? 0 : (sentBytes / size).clamp(0.0, 1.0).toDouble();
  bool get active => status == UploadStatus.queued || status == UploadStatus.uploading || status == UploadStatus.paused;
  bool get finished => status == UploadStatus.done || status == UploadStatus.canceled;
}

class StorageProvider extends ChangeNotifier {
  StorageProvider({
    required StorageService storages,
    required NodeService node,
    required StorageItem initial,
    SecureStore? secure,
  })  : _storages = storages,
        _node = node,
        _secure = secure,
        _item = initial {
    unawaited(_loadSort());
  }

  final StorageService _storages;
  final NodeService _node;
  final SecureStore? _secure;

  Uint8List? _e2eeKey;
  String? _e2eeKeyText;

  StorageItem _item;
  StorageState? _state;
  OwnerGrant? _grant;
  bool _loading = false;
  String? _error;
  bool _disposed = false;

  final List<UploadTask> _uploads = [];
  final List<FileDownload> _downloads = [];
  final DownloadService _files = DownloadService();
  bool _pumping = false;

  static const _sortKey = 'tmps.file_sort';
  FileSort _sort = FileSort.dateDesc;
  String _query = '';
  final Set<String> _selected = {};

  WebSocketChannel? _socket;
  StreamSubscription? _events;
  Timer? _reconnect;
  Timer? _debounce;
  int _attempt = 0;
  bool _live = false;

  bool get live => _live;

  StorageItem get item => _item;
  StorageState? get state => _state;
  bool get loading => _loading;
  String? get error => _error;
  List<UploadTask> get uploads => List.unmodifiable(_uploads);
  List<FileDownload> get downloads => List.unmodifiable(_downloads);
  List<StorageFile> get files => _state?.files ?? const [];

  // ---- Сквозное шифрование ----

  /// Хранилище зашифровано (флаг приходит и из списка хранилищ, и из состояния ноды).
  bool get e2ee => _item.e2ee || (_state?.e2ee ?? false);

  /// Зашифрованное хранилище, а ключа на этом устройстве нет: файлы не прочитать и не загрузить.
  bool get e2eeNeedsKey => e2ee && _e2eeKey == null;

  /// Ссылка на хранилище; в зашифрованном добавляется ключ (`#k=…`), если он есть на устройстве.
  String get shareUrl {
    final key = _e2eeKeyText;
    return e2ee && key != null ? '${_item.url}#k=$key' : _item.url;
  }

  /// Принимает ключ или ссылку с `#k=…`. false, если ключ не подходит к этому хранилищу.
  Future<bool> setE2eeKey(String text) async {
    final raw = E2ee.extractKey(text);
    if (raw == null || !await _acceptKey(raw)) return false;
    try {
      await _secure?.writeE2eeKey(_item.code, raw);
    } catch (_) {}
    await _decorate();
    _ping();
    return true;
  }

  Future<bool> _acceptKey(String raw) async {
    try {
      final key = E2ee.keyBytes(raw);
      final check = _state?.e2eeCheck;
      if (check != null && !await E2ee.verifyCheck(key, check)) return false;
      _e2eeKey = key;
      _e2eeKeyText = raw;
      return true;
    } on E2eeException {
      return false;
    }
  }

  Future<void> _loadSavedKey() async {
    if (_e2eeKey != null) return;
    try {
      final raw = await _secure?.readE2eeKey(_item.code);
      if (raw != null) await _acceptKey(raw);
    } catch (_) {}
  }

  /// Расшифровывает имена файлов; без ключа показывает заглушку.
  Future<void> _decorate() async {
    final state = _state;
    if (state == null || !e2ee) return;
    final key = _e2eeKey;
    final next = <StorageFile>[];
    for (final file in state.files) {
      if (file.chunkSize != null || !E2ee.isEncryptedName(file.name)) {
        next.add(file);
        continue;
      }
      if (key == null) {
        next.add(file.copyWith(displayName: 'Зашифрованный файл'));
        continue;
      }
      final decoded = await E2ee.decryptName(key, file.name);
      if (decoded == null) {
        next.add(file.copyWith(displayName: 'Не удалось расшифровать имя'));
        continue;
      }
      next.add(file.copyWith(
        displayName: decoded.name,
        chunkSize: decoded.chunkSize,
        plainSize: E2ee.plainSize(file.size, decoded.chunkSize),
        kind: kindForName(decoded.name),
      ));
    }
    _state = state.withFiles(next);
  }

  Future<void> _prepareE2ee() async {
    if (!e2ee) return;
    await _loadSavedKey();
    await _decorate();
  }

  // ---- Поиск и сортировка ----

  FileSort get sort => _sort;
  String get query => _query;
  bool get filtering => _query.trim().isNotEmpty;

  /// Файлы с учётом поиска и выбранной сортировки.
  List<StorageFile> get visibleFiles {
    final needle = _query.trim().toLowerCase();
    final list = [
      for (final file in files)
        if (needle.isEmpty || file.title.toLowerCase().contains(needle)) file,
    ];
    list.sort(_compare);
    return list;
  }

  int _compare(StorageFile a, StorageFile b) {
    int byName() => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    int then(int primary) => primary != 0 ? primary : byName();
    switch (_sort) {
      case FileSort.dateDesc:
        return then(b.modifiedAt.compareTo(a.modifiedAt));
      case FileSort.dateAsc:
        return then(a.modifiedAt.compareTo(b.modifiedAt));
      case FileSort.nameAsc:
        return byName();
      case FileSort.nameDesc:
        return -byName();
      case FileSort.sizeDesc:
        return then(b.shownSize.compareTo(a.shownSize));
      case FileSort.sizeAsc:
        return then(a.shownSize.compareTo(b.shownSize));
      case FileSort.type:
        return then(a.kind.compareTo(b.kind));
    }
  }

  Future<void> _loadSort() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_sortKey);
      if (index != null && index >= 0 && index < FileSort.values.length) {
        _sort = FileSort.values[index];
        _ping();
      }
    } catch (_) {}
  }

  Future<void> setSort(FileSort value) async {
    _sort = value;
    _ping();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_sortKey, value.index);
    } catch (_) {}
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    // Выбранные файлы могли скрыться из списка, поэтому выбор сбрасываем.
    _selected.clear();
    _ping();
  }

  // ---- Выбор нескольких файлов ----

  bool get selecting => _selected.isNotEmpty;
  int get selectedCount => _selected.length;
  bool isSelected(String name) => _selected.contains(name);

  List<StorageFile> get selectedFiles =>
      [for (final file in visibleFiles) if (_selected.contains(file.name)) file];

  void toggleSelected(String name) {
    if (!_selected.remove(name)) _selected.add(name);
    _ping();
  }

  void selectAllVisible() {
    _selected.addAll(visibleFiles.map((f) => f.name));
    _ping();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    _ping();
  }

  void _pruneSelection() {
    if (_selected.isEmpty) return;
    final names = files.map((f) => f.name).toSet();
    _selected.removeWhere((name) => !names.contains(name));
  }

  void downloadSelected() {
    final picked = selectedFiles;
    clearSelection();
    for (final file in picked) {
      unawaited(download(file));
    }
  }

  Future<void> deleteSelected() async {
    final names = _selected.toList();
    await deleteFiles(names);
    _selected.removeAll(names);
    _ping();
  }

  String selectedLinks() =>
      selectedFiles.map((f) => fileUri(f).toString()).join('\n');

  bool get hasActiveUploads => _uploads.any((t) => t.active);

  int get usedBytes => _state?.usedBytes ?? _item.usedBytes;
  int get quotaBytes => _state?.quotaBytes ?? _item.quotaBytes;
  int get freeBytes => max(0, quotaBytes - usedBytes);

  void _ping() {
    if (!_disposed) notifyListeners();
  }

  Future<OwnerGrant> _ownerGrant({bool force = false}) async {
    final current = _grant;
    if (!force && current != null && !current.stale) return current;
    final fresh = await _storages.ownerGrant(_item.code);
    _grant = fresh;
    return fresh;
  }

  Future<T> _withGrant<T>(Future<T> Function(OwnerGrant grant) action) async {
    final grant = await _ownerGrant();
    try {
      return await action(grant);
    } on ApiException catch (e) {
      if (e.status != 403) rethrow;
      final fresh = await _ownerGrant(force: true);
      return action(fresh);
    }
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = null;
      _ping();
    }
    try {
      _item = await _storages.get(_item.code);
      _state = await _withGrant((grant) => _node.state(_item.code, grant));
      await _prepareE2ee();
      _pruneSelection();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      _ping();
    }
  }

  void applyItem(StorageItem item) {
    _item = item;
    _ping();
  }

  Uri fileUri(StorageFile file, {bool download = true}) =>
      _node.fileUri(_item.code, file.name, download: download);

  /// Заголовки владельца для предпросмотра файла по ссылке.
  /// [refresh] запрашивает новый ключ, если прежний перестал подходить.
  Future<Map<String, String>> previewHeaders({bool refresh = false}) async {
    final grant = await _ownerGrant(force: refresh);
    return _node.ownerHeaders(grant);
  }

  Future<void> download(StorageFile file) {
    if (!e2ee) {
      return _startDownload(file.name, () => _node.fileUri(_item.code, file.name));
    }
    final key = _e2eeKey;
    final chunk = file.chunkSize;
    if (key == null || chunk == null) {
      final failed = FileDownload(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_downloads.length}',
        name: file.title,
        build: () => _node.fileUri(_item.code, file.name),
        allowPause: false,
      )
        ..canPause = false
        ..error = 'Нужен ключ шифрования';
      _downloads.add(failed);
      _ping();
      return Future.value();
    }
    return _startDownload(
      file.title,
      () => _node.fileUri(_item.code, file.name),
      cipherName: file.name,
      decrypt: E2eeDownload(key: key, fileId: file.name, chunkSize: chunk, saveAs: file.title),
    );
  }

  Future<void> downloadArchive() {
    return _startDownload(
      'tmps-${_item.code}.zip',
      () => _node.archiveUri(_item.code),
      allowPause: false,
    );
  }

  Future<void> _startDownload(
    String name,
    Uri Function() build, {
    bool allowPause = true,
    String? cipherName,
    E2eeDownload? decrypt,
  }) {
    final job = FileDownload(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_downloads.length}',
      name: name,
      build: build,
      allowPause: allowPause,
      cipherName: cipherName,
      decrypt: decrypt,
    )..canPause = allowPause;
    _downloads.add(job);
    _ping();
    return _runDownload(job);
  }

  /// Запускает скачивание заново для неудавшегося или отменённого файла.
  Future<void> retryDownload(FileDownload job) {
    if (!job.canRetry) return Future.value();
    job
      ..error = null
      ..canceled = false
      ..paused = false
      ..hint = null
      ..handle = null
      ..pauseSupported = null
      ..progress = 0;
    _ping();
    return _runDownload(job);
  }

  Future<void> _runDownload(FileDownload job) async {
    try {
      final grant = await _ownerGrant();
      if (job.canceled) return;
      job.savedPath = await _files.save(
        url: job.build(),
        headers: _node.ownerHeaders(grant),
        filename: job.cipherName ?? job.name,
        displayName: job.name,
        decrypt: job.decrypt,
        onPhase: (hint) {
          job.hint = hint;
          _ping();
        },
        allowPause: job.allowPause,
        onStart: (handle) {
          job.handle = handle;
          if (job.canceled) unawaited(_files.cancel(handle));
        },
        onPaused: (paused) {
          job.paused = paused;
          if (paused) job.hint = null;
          _ping();
        },
        onPauseSupport: (supported) {
          job.pauseSupported = supported;
          _ping();
        },
        onProgress: (value) {
          job.progress = value.clamp(0.0, 1.0).toDouble();
          _ping();
        },
      );
      job.progress = 1;
    } on DownloadCanceled {
      job.canceled = true;
    } on ApiException catch (e) {
      job.error = e.message;
    } on DownloadFailure catch (e) {
      job.error = e.message;
    } catch (_) {
      job.error = 'Не удалось скачать файл';
    } finally {
      _ping();
    }
  }

  Future<void> openDownload(FileDownload job) async {
    final path = job.savedPath;
    if (path == null) return;
    await DownloadService.openSaved(path);
  }

  Future<void> pauseDownload(FileDownload job) async {
    final handle = job.handle;
    if (handle == null || !job.running || job.paused || !job.pauseEnabled) return;
    final ok = await _files.pause(handle);
    job.hint = ok ? null : 'Для этого файла пауза недоступна';
    if (ok) job.paused = true;
    _ping();
  }

  Future<void> resumeDownload(FileDownload job) async {
    final handle = job.handle;
    if (handle == null || !job.running || !job.paused) return;
    final ok = await _files.resume(handle);
    job.hint = ok ? null : 'Не удалось продолжить, отмените и скачайте заново';
    if (ok) job.paused = false;
    _ping();
  }

  Future<void> cancelDownload(FileDownload job) async {
    if (!job.running) return;
    job.canceled = true;
    job.paused = false;
    job.hint = null;
    _ping();
    final handle = job.handle;
    if (handle != null) await _files.cancel(handle);
  }

  Future<void> pauseAllDownloads() async {
    await Future.wait(_downloads.where((j) => j.running && j.pauseEnabled && !j.paused).map(pauseDownload));
  }

  Future<void> resumeAllDownloads() async {
    await Future.wait(_downloads.where((j) => j.running && j.paused).map(resumeDownload));
  }

  Future<void> cancelAllDownloads() async {
    await Future.wait(_downloads.where((j) => j.running).toList().map(cancelDownload));
  }

  void forgetDownload(FileDownload job) {
    _downloads.remove(job);
    _ping();
  }

  void clearFinishedDownloads() {
    _downloads.removeWhere((d) => d.done || d.error != null || d.canceled);
    _ping();
  }

  Future<void> deleteFiles(List<String> names) async {
    await _withGrant((grant) => _node.deleteFiles(_item.code, grant, names));
    await load(silent: true);
  }

  void enqueue(Iterable<UploadSource> picked) {
    for (final source in picked) {
      _uploads.add(UploadTask(
        id: '${DateTime.now().microsecondsSinceEpoch}-${_uploads.length}',
        source: source,
      ));
    }
    _ping();
    unawaited(_pump());
  }

  void pause(UploadTask task) {
    if (task.status == UploadStatus.uploading || task.status == UploadStatus.queued) {
      task.status = UploadStatus.paused;
      task.triggerAbort();
      _ping();
    }
  }

  void resume(UploadTask task) {
    if (task.status == UploadStatus.paused || task.status == UploadStatus.error) {
      task.status = UploadStatus.queued;
      task.error = null;
      _ping();
      unawaited(_pump());
    }
  }

  void pauseAll() {
    for (final task in _uploads) {
      if (task.status == UploadStatus.uploading || task.status == UploadStatus.queued) {
        task.status = UploadStatus.paused;
        task.triggerAbort();
      }
    }
    _ping();
  }

  void resumeAll() {
    for (final task in _uploads) {
      if (task.status == UploadStatus.paused || task.status == UploadStatus.error) {
        task.status = UploadStatus.queued;
        task.error = null;
      }
    }
    _ping();
    unawaited(_pump());
  }

  Future<void> cancel(UploadTask task) async {
    if (task.status == UploadStatus.done || task.status == UploadStatus.canceled) return;
    final uid = task.uid;
    task.status = UploadStatus.canceled;
    task.triggerAbort();
    _ping();
    if (uid != null) {
      try {
        await _withGrant((grant) => _node.abortUpload(_item.code, grant, uid));
      } catch (_) {}
    }
  }

  Future<void> cancelAll() async {
    final tasks = _uploads.where((t) => t.active).toList();
    await Future.wait(tasks.map(cancel));
  }

  void clearFinished() {
    _uploads.removeWhere((t) => t.finished || t.status == UploadStatus.error);
    _ping();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (!_disposed) {
        UploadTask? next;
        for (final task in _uploads) {
          if (task.status == UploadStatus.queued) {
            next = task;
            break;
          }
        }
        if (next == null) break;
        await _runTask(next);
      }
    } finally {
      _pumping = false;
      if (!_disposed) await load(silent: true);
    }
  }

  /// Повторяет запрос при обрыве связи и ошибках сервера: до трёх раз с
  /// нарастающей паузой. Если отправку поставили на паузу или отменили,
  /// ожидание прерывается.
  Future<T> _transient<T>(UploadTask task, Future<T> Function() action) async {
    var attempt = 0;
    while (true) {
      try {
        return await action();
      } on ApiException catch (e) {
        final transient = e.status == 0 || e.status >= 500;
        if (!transient || attempt >= 3 || _disposed) rethrow;
        attempt++;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
        if (task.status != UploadStatus.uploading || _disposed) {
          throw RequestAbortedException();
        }
      }
    }
  }

  /// Проверяет, что сервер выдал ту же разбивку на куски, с которой посчитан размер шифртекста.
  void _checkWire(UploadSession session, int wireChunk, int plainSize) {
    if (session.chunkSize != wireChunk || session.totalChunks != E2ee.chunkCount(plainSize, wireChunk)) {
      throw ApiException('Размер части на сервере изменился, откройте хранилище заново');
    }
  }

  Future<void> _runTask(UploadTask task) async {
    final key = _e2eeKey;
    if (e2ee && key == null) {
      task.status = UploadStatus.error;
      task.error = 'Нужен ключ шифрования';
      _ping();
      return;
    }
    task.armAbort();
    task.status = UploadStatus.uploading;
    task.error = null;
    _ping();

    final reader = _ChunkReader(task.source);
    try {
      await reader.open();

      // В зашифрованном хранилище на сервер уходит шифртекст: другое имя, другой размер, другие куски.
      final wireChunk = _state?.chunkSize ?? 8 * 1024 * 1024;
      Future<String> wireName() async =>
          key == null ? task.name : await E2ee.encryptName(key, task.name, wireChunk);
      final wireSize = key == null ? task.size : E2ee.encryptedSize(task.size, wireChunk);

      final startedUid = task.uid;
      final resumed = startedUid == null
          ? null
          : await _withGrant((grant) => _node.uploadState(_item.code, grant, startedUid));
      UploadSession session = resumed ??
          await _withGrant((grant) async =>
              _node.initUpload(_item.code, grant, await wireName(), wireSize));
      if (key != null) _checkWire(session, wireChunk, task.size);
      task.uid = session.uid;

      int step() => key == null ? session.chunkSize : E2ee.plainChunkSize(session.chunkSize);

      var received = session.received;
      task.sentBytes = min(task.size, received.length * step());
      _ping();

      for (var index = 0; index < session.totalChunks; index++) {
        if (_disposed) return;
        if (task.status == UploadStatus.paused) return;
        if (task.status == UploadStatus.canceled) return;
        if (received.contains(index)) continue;

        final offset = index * step();
        final length = min(step(), task.size - offset);
        final bytes = await reader.read(offset, length);
        if (bytes.length != length) {
          throw ApiException('Файл изменился или стал недоступен');
        }

        final uid = session.uid;
        final List<int> payload = key == null
            ? bytes
            : await E2ee.encryptChunkInIsolate(
                key,
                bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
                index,
                session.totalChunks,
                session.name,
              );
        try {
          await _transient(
            task,
            () => _withGrant(
              (grant) => _node.putChunk(
                _item.code,
                grant,
                uid,
                index,
                payload,
                abort: task.abortSignal,
              ),
            ),
          );
        } on RequestAbortedException {
          return;
        } on ApiException catch (e) {
          if (!e.notFound) rethrow;
          if (task.status != UploadStatus.uploading) return;

          session = await _withGrant(
            (grant) async => _node.initUpload(_item.code, grant, await wireName(), wireSize),
          );
          if (key != null) _checkWire(session, wireChunk, task.size);
          task.uid = session.uid;
          received = session.received;
          task.sentBytes = 0;
          index = -1;
          _ping();
          continue;
        }

        received = {...received, index};
        task.sentBytes = min(task.size, task.sentBytes + length);
        _ping();
      }

      if (task.status != UploadStatus.uploading) return;
      final finalUid = session.uid;
      await _withGrant((grant) => _node.completeUpload(_item.code, grant, finalUid));
      task.status = UploadStatus.done;
      task.sentBytes = task.size;
    } on ApiException catch (e) {
      task.status = UploadStatus.error;
      task.error = e.message;
    } on E2eeException catch (e) {
      task.status = UploadStatus.error;
      task.error = e.message;
    } catch (_) {
      task.status = UploadStatus.error;
      task.error = 'Не удалось прочитать файл';
    } finally {
      await reader.close();
      _ping();
    }
  }

  Future<void> connect() async {
    if (_disposed || _socket != null) return;
    try {
      final grant = await _ownerGrant();
      if (_disposed) return;
      final socket = _node.watch(_item.code, grant);
      _socket = socket;
      _events = socket.stream.listen(
        _onEvent,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _onClosed();
    }
  }

  void _onEvent(dynamic raw) {
    if (_disposed || raw is! String) return;
    _attempt = 0;
    if (!_live) {
      _live = true;
      _ping();
    }
    Map<String, dynamic> event;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return;
      event = parsed;
    } catch (_) {
      return;
    }
    switch (event['type']) {
      case 'pong':
        return;
      case 'hello':
        _state = StorageState.fromJson(event);
        _pruneSelection();
        _error = null;
        _ping();
        if (e2ee) {
          unawaited(_prepareE2ee().then((_) {
            _pruneSelection();
            _ping();
          }));
        }
        return;
      default:
        _scheduleReload();
    }
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!_disposed) unawaited(load(silent: true));
    });
  }

  void _onClosed() {
    _live = false;
    _events?.cancel();
    _events = null;
    _socket = null;
    if (_disposed) return;
    _ping();
    _attempt = min(_attempt + 1, 5);
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: 2 << (_attempt - 1)), () {
      if (!_disposed) unawaited(connect());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _reconnect?.cancel();
    _events?.cancel();
    try {
      _socket?.sink.close();
    } catch (_) {}
    super.dispose();
  }
}
