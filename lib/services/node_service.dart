import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/storage.dart';
import '../models/storage_file.dart';
import 'api_client.dart';

class NodeService {
  NodeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Uri _uriFromBase(
    String baseUrl,
    String path, [
    Map<String, String>? query,
  ]) {
    final base = Uri.parse(baseUrl);
    if (!base.hasScheme || base.host.isEmpty) {
      throw ApiException('Сервер не вернул адрес хранилища');
    }
    final root = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$root$path',
      queryParameters: query == null || query.isEmpty ? null : query,
      fragment: '',
    );
  }

  /// Адрес ноды не зашит в приложении: сервер выдаёт его в owner grant.
  Uri _uri(OwnerGrant grant, String path, [Map<String, String>? query]) =>
      _uriFromBase(grant.baseUrl, path, query);

  Map<String, String> _headers(OwnerGrant grant, {String? contentType}) {
    final headers = <String, String>{
      grant.header: grant.token,
      'Accept': 'application/json',
    };
    if (contentType != null) headers['Content-Type'] = contentType;
    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = const {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final parsed = jsonDecode(utf8.decode(response.bodyBytes));
        if (parsed is Map<String, dynamic>) data = parsed;
      } catch (_) {
        data = const {};
      }
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        data['error'] as String? ?? 'Хранилище вернуло ошибку (${response.statusCode})',
        status: response.statusCode,
      );
    }
    return data;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiException {
      rethrow;
    } on http.RequestAbortedException {
      rethrow;
    } on TimeoutException {
      throw ApiException('Хранилище не ответило вовремя');
    } catch (_) {
      throw ApiException('Нет связи с хранилищем');
    }
  }

  Future<StorageState> state(String code, OwnerGrant grant) {
    return _guard(() async {
      final response = await _client
          .get(_uri(grant, '/api/state'), headers: _headers(grant))
          .timeout(const Duration(seconds: 20));
      return StorageState.fromJson(_decode(response));
    });
  }

  Future<UploadSession> initUpload(String code, OwnerGrant grant, String name, int size) {
    return _guard(() async {
      final response = await _client
          .post(
            _uri(grant, '/api/upload'),
            headers: _headers(grant, contentType: 'application/json; charset=utf-8'),
            body: jsonEncode({'name': name, 'size': size}),
          )
          .timeout(const Duration(seconds: 30));
      return UploadSession.fromJson(_decode(response));
    });
  }

  Future<UploadSession?> uploadState(String code, OwnerGrant grant, String uid) async {
    try {
      return await _guard(() async {
        final response = await _client
            .get(_uri(grant, '/api/upload/$uid'), headers: _headers(grant))
            .timeout(const Duration(seconds: 20));
        return UploadSession.fromJson(_decode(response));
      });
    } on ApiException catch (e) {
      if (e.notFound) return null;
      rethrow;
    }
  }

  Future<void> putChunk(
    String code,
    OwnerGrant grant,
    String uid,
    int index,
    List<int> bytes, {
    Duration timeout = const Duration(minutes: 3),
    Future<void>? abort,
  }) {
    return _guard(() async {
      final request = http.AbortableRequest(
        'PUT',
        _uri(grant, '/api/upload/$uid/$index'),
        abortTrigger: abort,
      )
        ..headers.addAll(_headers(grant, contentType: 'application/octet-stream'))
        ..bodyBytes = bytes;
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed).timeout(timeout);
      _decode(response);
    });
  }

  Future<void> completeUpload(String code, OwnerGrant grant, String uid) {
    return _guard(() async {
      final response = await _client
          .post(_uri(grant, '/api/upload/$uid/complete'), headers: _headers(grant))
          .timeout(const Duration(minutes: 2));
      _decode(response);
    });
  }

  Future<void> abortUpload(String code, OwnerGrant grant, String uid) async {
    try {
      await _guard(() async {
        final response = await _client
            .delete(_uri(grant, '/api/upload/$uid'), headers: _headers(grant))
            .timeout(const Duration(seconds: 20));
        _decode(response);
      });
    } on ApiException catch (_) {}
  }

  Future<List<String>> deleteFiles(String code, OwnerGrant grant, List<String> names) {
    return _guard(() async {
      final response = await _client
          .post(
            _uri(grant, '/api/delete'),
            headers: _headers(grant, contentType: 'application/json; charset=utf-8'),
            body: jsonEncode({'names': names}),
          )
          .timeout(const Duration(seconds: 60));
      final data = _decode(response);
      return ((data['removed'] as List?) ?? const []).map((e) => e.toString()).toList();
    });
  }

  Uri fileUri(String baseUrl, String name, {bool download = true}) =>
      _uriFromBase(baseUrl, '/f/$name', download ? const {'dl': '1'} : null);

  Uri archiveUri(String baseUrl) => _uriFromBase(baseUrl, '/api/zip/all');

  WebSocketChannel watch(String code, OwnerGrant grant) {
    final uri = _uri(grant, '/ws');
    final socket = uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
    return IOWebSocketChannel.connect(
      socket,
      headers: {grant.header: grant.token},
      pingInterval: const Duration(seconds: 30),
      connectTimeout: const Duration(seconds: 15),
    );
  }

  Map<String, String> ownerHeaders(OwnerGrant grant) => {grant.header: grant.token};
}
