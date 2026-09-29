import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const String kBaseUrl = 'https://tmps.epsiquad.com';
const String kApiPrefix = '/api/v1';

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.code = 'error'});

  final String message;
  final int status;
  final String code;

  bool get unauthorized => status == 401;
  bool get notFound => status == 404;

  @override
  String toString() => message;
}

typedef TokenReader = String? Function();
typedef TokenRefresher = Future<bool> Function();

http.Client _newClient() {
  final io = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 8);
  return IOClient(io);
}

class ApiClient {
  ApiClient({
    http.Client? client,
    required TokenReader accessToken,
    required TokenRefresher refresh,
    this.baseUrl = kBaseUrl,
  })  : _client = client ?? _newClient(),
        _fixedClient = client != null,
        _accessToken = accessToken,
        _refresh = refresh;

  http.Client _client;
  final bool _fixedClient;
  final TokenReader _accessToken;
  final TokenRefresher _refresh;
  final String baseUrl;

  Future<bool>? _refreshing;

  void close() => _client.close();

  void _resetConnections() {
    if (_fixedClient) return;
    try {
      _client.close();
    } catch (_) {}
    _client = _newClient();
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: path.startsWith('/') ? path : '/$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Map<String, String> _headers({bool auth = true, bool json = true}) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (json) headers['Content-Type'] = 'application/json; charset=utf-8';
    if (auth) {
      final token = _accessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<bool> _refreshOnce() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final started = _refresh().whenComplete(() => _refreshing = null);
    _refreshing = started;
    return started;
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Future<http.Response> send() {
      final uri = _uri(path, query);
      final headers = _headers(auth: auth);
      final payload = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'GET':
          return _client.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          return _client.post(uri, headers: headers, body: payload).timeout(timeout);
        case 'PATCH':
          return _client.patch(uri, headers: headers, body: payload).timeout(timeout);
        case 'DELETE':
          return _client.delete(uri, headers: headers, body: payload).timeout(timeout);
        default:
          throw ApiException('Метод $method не поддерживается');
      }
    }

    var response = await _sendOnce(send);

    if (response.statusCode == 401 && auth) {
      final ok = await _refreshOnce();
      if (ok) response = await _sendOnce(send);
    }
    return _decode(response);
  }

  Future<http.Response> _sendOnce(Future<http.Response> Function() send) async {
    try {
      return await send();
    } on TimeoutException {
      _resetConnections();
    } on SocketException {
      _resetConnections();
    } on HttpException {
      _resetConnections();
    } catch (_) {
      throw ApiException('Нет связи с сервером. Проверьте интернет');
    }

    try {
      return await send();
    } on TimeoutException {
      throw ApiException('Сервер не ответил вовремя. Проверьте соединение');
    } catch (_) {
      throw ApiException('Нет связи с сервером. Проверьте интернет');
    }
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
        data['error'] as String? ?? 'Ошибка сервера (${response.statusCode})',
        status: response.statusCode,
        code: data['code'] as String? ?? 'error',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query, bool auth = true}) =>
      request('GET', path, query: query, auth: auth);

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, bool auth = true}) =>
      request('POST', path, body: body, auth: auth);

  Future<Map<String, dynamic>> patch(String path, {Map<String, dynamic>? body}) =>
      request('PATCH', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => request('DELETE', path);
}
