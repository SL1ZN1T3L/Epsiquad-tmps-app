import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'preview_service.dart';

class ZipEntryInfo {
  const ZipEntryInfo({
    required this.name,
    required this.size,
    required this.compressedSize,
    required this.isDirectory,
    required this.encrypted,
    required this.modified,
  });

  final String name;
  final int size;
  final int compressedSize;
  final bool isDirectory;
  final bool encrypted;
  final DateTime? modified;

  /// Последний сегмент пути без завершающего «/».
  String get baseName {
    final clean = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
    final slash = clean.lastIndexOf('/');
    return slash < 0 ? clean : clean.substring(slash + 1);
  }

  int get depth {
    final clean = name.endsWith('/') ? name.substring(0, name.length - 1) : name;
    return '/'.allMatches(clean).length;
  }
}

class ZipListing {
  const ZipListing({required this.entries, required this.total});

  final List<ZipEntryInfo> entries;

  /// Сколько записей заявлено в архиве (может быть больше, чем прочитано).
  final int total;

  bool get truncated => total > entries.length;
  int get fileCount => entries.where((e) => !e.isDirectory).length;
  int get directoryCount => entries.where((e) => e.isDirectory).length;
  int get unpackedSize =>
      entries.fold<int>(0, (sum, e) => e.isDirectory ? sum : sum + e.size);
}

/// Читает оглавление ZIP, не скачивая архив целиком: берёт конец файла
/// (там лежит центральный каталог) обычными Range-запросами.
class ZipReader {
  static const _tailBytes = 66 * 1024; // EOCD (22 Б) + комментарий до 65535 Б
  static const _maxDirectoryBytes = 16 * 1024 * 1024;
  static const _maxEntries = 20000;
  static const _wholeFileLimit = 64 * 1024 * 1024;
  static const _timeout = Duration(seconds: 30);

  static Future<ZipListing> list(
    Uri uri,
    Map<String, String> headers,
    int size,
  ) async {
    final source = _RangeSource(uri, headers, size);
    try {
      return await _list(source, size);
    } on PreviewException {
      rethrow;
    } on TimeoutException {
      throw PreviewException('Хранилище не ответило вовремя');
    } catch (_) {
      throw PreviewException('Не удалось прочитать архив');
    } finally {
      source.close();
    }
  }

  static Future<ZipListing> _list(_RangeSource source, int size) async {
    if (size < 22) throw PreviewException('Файл не похож на ZIP-архив');

    final tailLength = min(size, _tailBytes);
    final tailStart = size - tailLength;
    final tail = await source.read(tailStart, tailLength);

    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 && tail[i + 1] == 0x4b && tail[i + 2] == 0x05 && tail[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw PreviewException('Файл не похож на ZIP-архив');

    final tailData = ByteData.sublistView(tail);
    var total = tailData.getUint16(eocd + 10, Endian.little);
    var directorySize = tailData.getUint32(eocd + 12, Endian.little);
    var directoryOffset = tailData.getUint32(eocd + 16, Endian.little);

    final needsZip64 =
        total == 0xFFFF || directorySize == 0xFFFFFFFF || directoryOffset == 0xFFFFFFFF;
    if (needsZip64) {
      final locator = eocd - 20;
      if (locator >= 0 && tailData.getUint32(locator, Endian.little) == 0x07064b50) {
        final recordOffset = tailData.getUint64(locator + 8, Endian.little);
        final record = await source.read(recordOffset, 56);
        if (record.length >= 56) {
          final recordData = ByteData.sublistView(record);
          if (recordData.getUint32(0, Endian.little) == 0x06064b50) {
            total = recordData.getUint64(32, Endian.little);
            directorySize = recordData.getUint64(40, Endian.little);
            directoryOffset = recordData.getUint64(48, Endian.little);
          }
        }
      }
    }

    if (directoryOffset + directorySize > size) {
      throw PreviewException('Архив повреждён или не дописан');
    }
    if (directorySize > _maxDirectoryBytes) {
      throw PreviewException('В архиве слишком много файлов для предпросмотра');
    }

    final Uint8List directory;
    if (directoryOffset >= tailStart) {
      final from = directoryOffset - tailStart;
      directory = Uint8List.sublistView(tail, from, from + directorySize);
    } else {
      directory = await source.read(directoryOffset, directorySize);
    }

    final entries = _parseDirectory(directory);
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ZipListing(entries: entries, total: total);
  }

  static List<ZipEntryInfo> _parseDirectory(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final entries = <ZipEntryInfo>[];
    var pos = 0;
    while (pos + 46 <= bytes.length && entries.length < _maxEntries) {
      if (data.getUint32(pos, Endian.little) != 0x02014b50) break;
      final flags = data.getUint16(pos + 8, Endian.little);
      final time = data.getUint16(pos + 12, Endian.little);
      final date = data.getUint16(pos + 14, Endian.little);
      var compressed = data.getUint32(pos + 20, Endian.little);
      var uncompressed = data.getUint32(pos + 24, Endian.little);
      final nameLength = data.getUint16(pos + 28, Endian.little);
      final extraLength = data.getUint16(pos + 30, Endian.little);
      final commentLength = data.getUint16(pos + 32, Endian.little);

      final nameStart = pos + 46;
      final extraStart = nameStart + nameLength;
      final next = extraStart + extraLength + commentLength;
      if (next > bytes.length) break;

      if (uncompressed == 0xFFFFFFFF || compressed == 0xFFFFFFFF) {
        var cursor = extraStart;
        final extraEnd = extraStart + extraLength;
        while (cursor + 4 <= extraEnd) {
          final id = data.getUint16(cursor, Endian.little);
          final length = data.getUint16(cursor + 2, Endian.little);
          if (id == 0x0001) {
            var offset = cursor + 4;
            final limit = min(cursor + 4 + length, extraEnd);
            if (uncompressed == 0xFFFFFFFF && offset + 8 <= limit) {
              uncompressed = data.getUint64(offset, Endian.little);
              offset += 8;
            }
            if (compressed == 0xFFFFFFFF && offset + 8 <= limit) {
              compressed = data.getUint64(offset, Endian.little);
            }
            break;
          }
          cursor += 4 + length;
        }
      }

      final nameBytes = Uint8List.sublistView(bytes, nameStart, extraStart);
      final name = _decodeName(nameBytes, utf8Flag: flags & 0x0800 != 0);
      entries.add(ZipEntryInfo(
        name: name,
        size: uncompressed,
        compressedSize: compressed,
        isDirectory: name.endsWith('/'),
        encrypted: flags & 0x0001 != 0,
        modified: _dosDateTime(date, time),
      ));
      pos = next;
    }
    return entries;
  }

  static String _decodeName(Uint8List bytes, {required bool utf8Flag}) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      // Старые архиваторы пишут имена в DOS-кодировке. Показываем как есть.
      return utf8Flag ? utf8.decode(bytes, allowMalformed: true) : latin1.decode(bytes);
    }
  }

  static DateTime? _dosDateTime(int date, int time) {
    final month = (date >> 5) & 0x0F;
    final day = date & 0x1F;
    if (month < 1 || month > 12 || day < 1) return null;
    return DateTime(
      ((date >> 9) & 0x7F) + 1980,
      month,
      day,
      (time >> 11) & 0x1F,
      (time >> 5) & 0x3F,
      (time & 0x1F) * 2,
    );
  }
}

class _RangeSource {
  _RangeSource(this.uri, this.headers, this.size);

  final Uri uri;
  final Map<String, String> headers;
  final int size;
  final http.Client _client = http.Client();

  /// Заполняется, если сервер проигнорировал Range и отдал файл целиком.
  Uint8List? _whole;

  void close() => _client.close();

  Future<Uint8List> read(int start, int length) async {
    final whole = _whole;
    if (whole != null) return _slice(whole, start, length);

    final request = http.Request('GET', uri)
      ..headers.addAll(headers)
      ..headers['Range'] = 'bytes=$start-${start + length - 1}';
    final response = await _client.send(request).timeout(ZipReader._timeout);
    if (response.statusCode >= 400) {
      throw PreviewException(previewStatusMessage(response.statusCode));
    }

    if (response.statusCode == 206) {
      return _collect(response.stream, length + 4096);
    }

    // 200: сервер не умеет частичную отдачу. Читаем целиком, но только небольшие файлы.
    if (size > ZipReader._wholeFileLimit) {
      throw PreviewException(
        'Сервер не поддерживает частичную загрузку, скачайте архив, чтобы посмотреть его',
      );
    }
    final all = await _collect(response.stream, ZipReader._wholeFileLimit);
    _whole = all;
    return _slice(all, start, length);
  }

  Uint8List _slice(Uint8List bytes, int start, int length) {
    if (start >= bytes.length) return Uint8List(0);
    return Uint8List.sublistView(bytes, start, min(start + length, bytes.length));
  }

  Future<Uint8List> _collect(Stream<List<int>> stream, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream.timeout(const Duration(seconds: 45))) {
      builder.add(chunk);
      if (builder.length > limit) {
        throw PreviewException('Хранилище вернуло больше данных, чем нужно');
      }
    }
    return builder.toBytes();
  }
}
