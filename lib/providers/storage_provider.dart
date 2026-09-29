import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/storage.dart';
import '../models/storage_file.dart';
import '../services/api_client.dart';
import '../services/download_service.dart';
import '../services/node_service.dart';
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

class FileDownload {
  FileDownload({required this.id, required this.name});

  final String id;
  final String name;

  double progress = 0;
  String? savedPath;
  String? error;

  bool get done => savedPath != null;
  bool get running => savedPath == null && error == null;
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

  double get progress => size <= 0 ? 0 : (sentBytes / size).clamp(0.0, 1.0).toDouble();
  bool get active => status == UploadStatus.queued || status == UploadStatus.uploading || status == UploadStatus.paused;
  bool get finished => status == UploadStatus.done || status == UploadStatus.canceled;
}

class StorageProvider extends ChangeNotifier {
  StorageProvider({
    required StorageService storages,
    required NodeService node,
    required StorageItem initial,
  })  : _storages = storages,
        _node = node,
        _item = initial;

  final StorageService _storages;
  final NodeService _node;

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

  Future<void> download(StorageFile file) {
    return _startDownload(file.name, () => _node.fileUri(_item.code, file.name));
  }

  Future<void> downloadArchive() {
    return _startDownload('tmps-${_item.code}.zip', () => _node.archiveUri(_item.code));
  }

  Future<void> _startDownload(String name, Uri Function() build) async {
    final job = FileDownload(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_downloads.length}',
      name: name,
    );
    _downloads.add(job);
    _ping();
    try {
      final grant = await _ownerGrant();
      job.savedPath = await _files.save(
        url: build(),
        headers: _node.ownerHeaders(grant),
        filename: name,
        onProgress: (value) {
          job.progress = value.clamp(0.0, 1.0).toDouble();
          _ping();
        },
      );
      job.progress = 1;
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

  void forgetDownload(FileDownload job) {
    _downloads.remove(job);
    _ping();
  }

  void clearFinishedDownloads() {
    _downloads.removeWhere((d) => d.done || d.error != null);
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
    final uid = task.uid;
    task.status = UploadStatus.canceled;
    _ping();
    if (uid != null) {
      try {
        await _withGrant((grant) => _node.abortUpload(_item.code, grant, uid));
      } catch (_) {}
    }
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

  Future<void> _runTask(UploadTask task) async {
    task.status = UploadStatus.uploading;
    task.error = null;
    _ping();

    final reader = _ChunkReader(task.source);
    try {
      await reader.open();

      final startedUid = task.uid;
      final resumed = startedUid == null
          ? null
          : await _withGrant((grant) => _node.uploadState(_item.code, grant, startedUid));
      UploadSession session = resumed ??
          await _withGrant((grant) => _node.initUpload(_item.code, grant, task.name, task.size));
      task.uid = session.uid;

      var received = session.received;
      task.sentBytes = min(task.size, received.length * session.chunkSize);
      _ping();

      for (var index = 0; index < session.totalChunks; index++) {
        if (_disposed) return;
        if (task.status == UploadStatus.paused) return;
        if (task.status == UploadStatus.canceled) return;
        if (received.contains(index)) continue;

        final offset = index * session.chunkSize;
        final length = min(session.chunkSize, task.size - offset);
        final bytes = await reader.read(offset, length);
        if (bytes.length != length) {
          throw ApiException('Файл изменился или стал недоступен');
        }

        final uid = session.uid;
        try {
          await _withGrant((grant) => _node.putChunk(_item.code, grant, uid, index, bytes));
        } on ApiException catch (e) {
          if (!e.notFound) rethrow;

          session = await _withGrant(
            (grant) => _node.initUpload(_item.code, grant, task.name, task.size),
          );
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
        _error = null;
        _ping();
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
