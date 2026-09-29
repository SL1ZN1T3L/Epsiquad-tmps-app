import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/storage.dart';
import '../models/storage_file.dart';
import 'api_client.dart';

class NodeService {
  NodeService({http.Client? client, this.baseUrl = kBaseUrl})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  void close() => _client.close();

  Uri _uri(String code, String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '/$code$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

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
    } on TimeoutException {
      throw ApiException('Хранилище не ответило вовремя');
    } catch (_) {
      throw ApiException('Нет связи с хранилищем');
    }
  }

  Future<StorageState> state(String code, OwnerGrant grant) {
    return _guard(() async {
      final response = await _client
          .get(_uri(code, '/api/state'), headers: _headers(grant))
          .timeout(const Duration(seconds: 20));
      return StorageState.fromJson(_decode(response));
    });
  }

  Future<UploadSession> initUpload(String code, OwnerGrant grant, String name, int size) {
    return _guard(() async {
      final response = await _client
          .post(
            _uri(code, '/api/upload'),
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
            .get(_uri(code, '/api/upload/$uid'), headers: _headers(grant))
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
  }) {
    return _guard(() async {
      final response = await _client
          .put(
            _uri(code, '/api/upload/$uid/$index'),
            headers: _headers(grant, contentType: 'application/octet-stream'),
            body: bytes,
          )
          .timeout(timeout);
      _decode(response);
    });
  }

  Future<void> completeUpload(String code, OwnerGrant grant, String uid) {
    return _guard(() async {
      final response = await _client
          .post(_uri(code, '/api/upload/$uid/complete'), headers: _headers(grant))
          .timeout(const Duration(minutes: 2));
      _decode(response);
    });
  }

  Future<void> abortUpload(String code, OwnerGrant grant, String uid) async {
    try {
      await _guard(() async {
        final response = await _client
            .delete(_uri(code, '/api/upload/$uid'), headers: _headers(grant))
            .timeout(const Duration(seconds: 20));
        _decode(response);
      });
    } on ApiException catch (_) {}
  }

  Future<List<String>> deleteFiles(String code, OwnerGrant grant, List<String> names) {
    return _guard(() async {
      final response = await _client
          .post(
            _uri(code, '/api/delete'),
            headers: _headers(grant, contentType: 'application/json; charset=utf-8'),
            body: jsonEncode({'names': names}),
          )
          .timeout(const Duration(seconds: 60));
      final data = _decode(response);
      return ((data['removed'] as List?) ?? const []).map((e) => e.toString()).toList();
    });
  }

  Uri fileUri(String code, String name, {bool download = true}) {
    return _uri(code, '/f/$name', download ? const {'dl': '1'} : null);
  }

  Uri archiveUri(String code) => _uri(code, '/api/zip/all');

  WebSocketChannel watch(String code, OwnerGrant grant) {
    final base = Uri.parse(baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/$code/ws',
    );
    return IOWebSocketChannel.connect(
      uri,
      headers: {grant.header: grant.token},
      pingInterval: const Duration(seconds: 30),
      connectTimeout: const Duration(seconds: 15),
    );
  }

  Map<String, String> ownerHeaders(OwnerGrant grant) => {grant.header: grant.token};
}
