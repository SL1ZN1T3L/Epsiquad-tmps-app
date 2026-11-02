import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Адрес нужен только для первого подключения, входа и обновления сессии.
/// Авторизованные маршруты загружаются из OpenAPI после входа.
const String kBaseUrl = 'https://tmps.epsiquad.com';
const String kApiPrefix = '/api/v1';

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.code = 'error'});

  final String message;
  final int status;
  final String code;

  bool get unauthorized => status == 401;
  bool get notFound => status == 404;
  bool get invalidatesSession => status == 401 || status == 403;

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

class _ApiOperation {
  const _ApiOperation(this.method, this.path);

  final String method;
  final String path;
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
  String baseUrl;

  Future<bool>? _refreshing;
  bool _offline = false;
  Map<String, _ApiOperation> _operations = const {};

  /// Имена соответствуют функциям обработчиков серверного apiv1.py. FastAPI
  /// добавляет к ним путь и метод в operationId, поэтому ищем уникальный префикс.
  static const _requiredOperations = <String, String>{
    'auth_logout': 'POST',
    'me': 'GET',
    'list_devices': 'GET',
    'drop_device': 'DELETE',
    'list_plans': 'GET',
    'my_storages': 'GET',
    'create_storage': 'POST',
    'one_storage': 'GET',
    'storage_token': 'POST',
    'extend': 'POST',
    'change_plan': 'POST',
    'rename': 'PATCH',
    'set_access': 'PATCH',
    'set_password': 'POST',
    'rotate': 'POST',
    'delete_storage': 'DELETE',
  };

  void close() => _client.close();

  void setOffline(bool value) => _offline = value;

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

  /// Загружает авторизованный контракт после login/refresh. Конечные точки
  /// входа остаются bootstrap-маршрутами: без них невозможно получить сессию.
  Future<void> discover() async {
    final schema = await get('$kApiPrefix/openapi.json', auth: false);
    final paths = schema['paths'];
    if (paths is! Map) {
      throw ApiException('Сервер вернул некорректное описание API');
    }

    final found = <String, _ApiOperation>{};
    for (final entry in paths.entries) {
      final path = entry.key;
      final methods = entry.value;
      if (path is! String || methods is! Map) continue;
      for (final methodEntry in methods.entries) {
        final method = methodEntry.key.toString().toUpperCase();
        final operation = methodEntry.value;
        if (operation is! Map) continue;
        final id = operation['operationId'];
        if (id is! String || id.isEmpty) continue;
        for (final required in _requiredOperations.entries) {
          if (id == required.key || id.startsWith('${required.key}_')) {
            final existing = found[required.key];
            if (existing != null &&
                (existing.path != path || existing.method != method)) {
              throw ApiException('Описание API содержит неоднозначную операцию ${required.key}');
            }
            found[required.key] = _ApiOperation(method, path);
          }
        }
      }
    }

    for (final required in _requiredOperations.entries) {
      final operation = found[required.key];
      if (operation == null || operation.method != required.value) {
        throw ApiException('API сервера несовместимо с приложением: ${required.key}');
      }
    }

    // Если сервер объявляет canonical URL, используем его для дальнейших
    // запросов. Старая версия без servers продолжает работать с bootstrap URL.
    final servers = schema['servers'];
    if (servers is List && servers.isNotEmpty) {
      final first = servers.first;
      final raw = first is Map ? first['url'] : null;
      if (raw is String && raw.isNotEmpty) {
        final resolved = Uri.parse(baseUrl).resolve(raw);
        if (resolved.scheme == 'https' && resolved.host.isNotEmpty) {
          baseUrl = resolved.origin;
        }
      }
    }
    _operations = found;
  }

  /// WebSocket не входит в OpenAPI: выводим его из корня уже проверенного API.
  String get eventsPath {
    final operation = _operations['me'];
    if (operation == null) {
      throw ApiException('API ещё не загружено, обновите сессию');
    }
    final slash = operation.path.lastIndexOf('/');
    return '${operation.path.substring(0, slash)}/ws';
  }

  Future<Map<String, dynamic>> operation(
    String name, {
    Map<String, String>? parameters,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) {
    final operation = _operations[name];
    if (operation == null) {
      throw ApiException('API ещё не загружено, обновите сессию');
    }
    var path = operation.path;
    parameters?.forEach((key, value) {
      path = path.replaceAll('{$key}', Uri.encodeComponent(value));
    });
    if (path.contains('{') || path.contains('}')) {
      throw ApiException('Не удалось собрать адрес операции $name');
    }
    return request(operation.method, path, body: body, query: query);
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_offline) {
      throw ApiException('Сеть отключена в Dev Mode');
    }

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

    // Потерянный ответ не доказывает, что POST/PATCH/DELETE не выполнен.
    // Поэтому автоматически повторяем только чтение; после refresh разрешён
    // отдельный replay исходного запроса уже с новым access token.
    final allowRetry = method == 'GET';
    var response = await _sendOnce(send, allowRetry: allowRetry);

    if (response.statusCode == 401 && auth) {
      final ok = await _refreshOnce();
      if (ok) response = await _sendOnce(send, allowRetry: allowRetry);
    }
    return _decode(response);
  }

  Future<http.Response> _sendOnce(
    Future<http.Response> Function() send, {
    required bool allowRetry,
  }) async {
    try {
      return await send();
    } on TimeoutException catch (error, stackTrace) {
      developer.log(
        'Request timed out; resetting the HTTP connection',
        name: 'tmps.api',
        error: error,
        stackTrace: stackTrace,
      );
      _resetConnections();
      if (!allowRetry) {
        throw ApiException('Сервер не ответил вовремя. Проверьте соединение');
      }
    } on SocketException catch (error, stackTrace) {
      developer.log(
        'Network connection failed; resetting the HTTP connection',
        name: 'tmps.api',
        error: error,
        stackTrace: stackTrace,
      );
      _resetConnections();
      if (!allowRetry) {
        throw ApiException('Нет связи с сервером. Проверьте интернет');
      }
    } on HttpException catch (error, stackTrace) {
      developer.log(
        'HTTP connection failed; resetting the HTTP connection',
        name: 'tmps.api',
        error: error,
        stackTrace: stackTrace,
      );
      _resetConnections();
      if (!allowRetry) {
        throw ApiException('Нет связи с сервером. Проверьте интернет');
      }
    } catch (error, stackTrace) {
      developer.log(
        'Unexpected network error',
        name: 'tmps.api',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApiException('Нет связи с сервером. Проверьте интернет');
    }

    try {
      return await send();
    } on TimeoutException catch (error, stackTrace) {
      developer.log(
        'Retry timed out',
        name: 'tmps.api',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApiException('Сервер не ответил вовремя. Проверьте соединение');
    } catch (error, stackTrace) {
      developer.log(
        'Retry failed because the server is unreachable',
        name: 'tmps.api',
        error: error,
        stackTrace: stackTrace,
      );
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
