import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// Канал событий аккаунта (`/api/v1/ws`): сервер сообщает, что в других клиентах (сайт, другое устройство)
/// изменились хранилища, устройства или аккаунт. Само событие - только сигнал, данные перечитываются обычным API.
///
/// Канал сам переподключается с нарастающей паузой. Токен доступа живёт недолго: сервер закрывает канал, когда
/// он истёк, а [ensureToken] перед повторным подключением обновляет его обычным запросом.
class UserEvents {
  UserEvents({
    required this.token,
    required this.onEvent,
    this.onReconnect,
    this.ensureToken,
    this.baseUrl = kBaseUrl,
  });

  /// Текущий токен доступа.
  final String? Function() token;

  /// Пришло событие: `storages`, `devices` или `account`.
  final void Function(String type) onEvent;

  /// Связь восстановилась после обрыва: за это время могли быть пропущенные события, обновите всё.
  final void Function()? onReconnect;

  /// Обновляет токен доступа (любой обычный запрос с автоматическим обновлением).
  final Future<void> Function()? ensureToken;

  final String baseUrl;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  bool _running = false;
  bool _wasConnected = false;
  int _attempts = 0;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_connect());
  }

  void stop() {
    _running = false;
    _retry?.cancel();
    _retry = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  Future<void> _connect() async {
    if (!_running) return;
    if (_attempts > 0) {
      try {
        await ensureToken?.call();
      } catch (_) {}
      if (!_running) return;
    }
    final access = token();
    if (access == null) {
      _scheduleRetry();
      return;
    }
    final base = Uri.parse(baseUrl);
    final uri = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '$kApiPrefix/ws');
    try {
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $access'},
        pingInterval: const Duration(seconds: 25),
        connectTimeout: const Duration(seconds: 15),
      );
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (_) => _lost(channel),
        onDone: () => _lost(channel),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Object? data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (data is! Map) return;
    final type = data['type'];
    if (type is! String) return;
    if (type == 'hello') {
      if (_wasConnected) onReconnect?.call();
      _wasConnected = true;
      _attempts = 0;
      return;
    }
    onEvent(type);
  }

  void _lost(WebSocketChannel channel) {
    if (!identical(channel, _channel)) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running || _retry != null) return;
    _attempts++;
    final seconds = _attempts > 5 ? 30 : (1 << _attempts);
    _retry = Timer(Duration(seconds: seconds), () {
      _retry = null;
      unawaited(_connect());
    });
  }
}
