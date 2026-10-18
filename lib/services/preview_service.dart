import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class PreviewException implements Exception {
  PreviewException(this.message);

  final String message;

  @override
  String toString() => message;
}

String previewStatusMessage(int code) {
  switch (code) {
    case 401:
    case 403:
      return 'Нет доступа к файлу, откройте хранилище заново';
    case 404:
      return 'Файл уже удалён из хранилища';
    case 410:
      return 'Срок хранилища истёк';
    default:
      return 'Хранилище вернуло ошибку ($code)';
  }
}

/// Загрузка файла для предпросмотра. Заголовок владельца передаётся снаружи.
class PreviewLoader {
  static const _connectTimeout = Duration(seconds: 30);
  static const _idleTimeout = Duration(seconds: 45);

  static Future<http.StreamedResponse> _open(
    http.Client client,
    Uri uri,
    Map<String, String> headers, {
    int? rangeEnd,
  }) async {
    final request = http.Request('GET', uri)..headers.addAll(headers);
    if (rangeEnd != null) request.headers['Range'] = 'bytes=0-$rangeEnd';
    final response = await client.send(request).timeout(_connectTimeout);
    if (response.statusCode >= 400) {
      throw PreviewException(previewStatusMessage(response.statusCode));
    }
    return response;
  }

  /// Читает файл в память. При [allowTruncate] берёт только первые [maxBytes].
  static Future<Uint8List> loadBytes(
    Uri uri,
    Map<String, String> headers, {
    required int maxBytes,
    required bool allowTruncate,
    int? knownSize,
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final response = await _open(
        client,
        uri,
        headers,
        rangeEnd: allowTruncate ? maxBytes - 1 : null,
      );
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        builder.add(chunk);
        if (knownSize != null && knownSize > 0) {
          onProgress?.call((builder.length / knownSize).clamp(0.0, 1.0).toDouble());
        }
        if (builder.length > maxBytes) {
          if (!allowTruncate) {
            throw PreviewException('Файл слишком большой для предпросмотра');
          }
          break;
        }
      }
      var bytes = builder.toBytes();
      if (bytes.length > maxBytes) {
        bytes = Uint8List.sublistView(bytes, 0, maxBytes);
      }
      return bytes;
    } on PreviewException {
      rethrow;
    } on TimeoutException {
      throw PreviewException('Хранилище не ответило вовремя');
    } catch (_) {
      throw PreviewException('Не удалось загрузить файл');
    } finally {
      client.close();
    }
  }

  /// Сохраняет файл целиком во временный [target]. Нужен для PDF.
  static Future<void> loadToFile(
    Uri uri,
    Map<String, String> headers,
    File target, {
    required int maxBytes,
    int? knownSize,
    void Function(double progress)? onProgress,
  }) async {
    if (knownSize != null && knownSize > maxBytes) {
      throw PreviewException('Файл слишком большой для предпросмотра, скачайте его');
    }
    final client = http.Client();
    IOSink? sink;
    try {
      final response = await _open(client, uri, headers);
      await target.parent.create(recursive: true);
      sink = target.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        received += chunk.length;
        if (received > maxBytes) {
          throw PreviewException('Файл слишком большой для предпросмотра, скачайте его');
        }
        sink.add(chunk);
        if (knownSize != null && knownSize > 0) {
          onProgress?.call((received / knownSize).clamp(0.0, 1.0).toDouble());
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } on PreviewException {
      await _discard(sink, target);
      rethrow;
    } on TimeoutException {
      await _discard(sink, target);
      throw PreviewException('Хранилище не ответило вовремя');
    } catch (_) {
      await _discard(sink, target);
      throw PreviewException('Не удалось загрузить файл');
    } finally {
      client.close();
    }
  }

  static Future<void> _discard(IOSink? sink, File target) async {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      if (await target.exists()) await target.delete();
    } catch (_) {}
  }
}

/// Отрисовка страниц PDF системным android.graphics.pdf.PdfRenderer
/// (см. MainActivity.kt), без сторонних библиотек.
class PdfRendererService {
  static const _channel = MethodChannel('com.epsiquad.tmps/pdf');

  static Future<int> open(String path) async {
    final pages = await _channel.invokeMethod<int>('open', {'path': path});
    return pages ?? 0;
  }

  static Future<Uint8List> render(int index, int width) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'render',
      {'index': index, 'width': width},
    );
    if (bytes == null) throw PreviewException('Не удалось показать страницу');
    return bytes;
  }

  static Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {}
  }
}
