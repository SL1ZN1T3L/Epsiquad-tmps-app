import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Ошибка шифрования или расшифровки: неверный ключ, повреждённый или неполный файл.
class E2eeException implements Exception {
  E2eeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Расшифрованное имя файла и размер куска, с которым файл был зашифрован.
class E2eeName {
  const E2eeName(this.name, this.chunkSize);

  final String name;
  final int chunkSize;
}

/// Что нужно, чтобы расшифровать скачанный файл и сохранить его в «Загрузки».
class E2eeDownload {
  const E2eeDownload({
    required this.key,
    required this.fileId,
    required this.chunkSize,
    required this.saveAs,
  });

  final Uint8List key;

  /// Имя файла на сервере (токен `e2e1.…`): к нему привязаны все куски.
  final String fileId;
  final int chunkSize;

  /// Настоящее имя файла для «Загрузок».
  final String saveAs;
}

/// Сквозное шифрование хранилищ. Схема совпадает с сайтом (site/node/static/js/.clear_js/e2ee.js):
///
/// - ключ: 256 бит, живёт только в ссылке (`#k=…`) и на устройстве, сервер его не видит;
/// - файл режется так, чтобы зашифрованный кусок ровно совпадал с чанком загрузки:
///   запись = nonce(12) | AES-256-GCM | тег(16), AAD = `tmps-e2ee-v1|c|<индекс>|<всего>|<имя на сервере>`;
/// - имя шифруется в токен `e2e1.` + base64url(nonce | AES-GCM(JSON {n: имя, c: размер чанка}));
/// - проверочная запись из метаданных хранилища подтверждает, что ключ верный.
class E2ee {
  const E2ee._();

  static const String namePrefix = 'e2e1.';
  static const int overhead = 28;
  static const String _label = 'tmps-e2ee-v1';
  static const int _nameMaxBytes = 80;

  static final AesGcm _gcm = AesGcm.with256bits();

  static bool isEncryptedName(String name) => name.startsWith(namePrefix);

  // ---- Ключ ----

  static String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List _unb64u(String text) {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(text.trim())));
  }

  /// Новый случайный ключ в виде base64url без заполнения.
  static String generateKey() {
    final random = Random.secure();
    return _b64u(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  static Uint8List keyBytes(String key) {
    try {
      final raw = _unb64u(key);
      if (raw.length != 32) throw E2eeException('Некорректный ключ');
      return raw;
    } on FormatException {
      throw E2eeException('Некорректный ключ');
    }
  }

  static final RegExp _keyInLink = RegExp(r'(?:[#&?]|^)k=([A-Za-z0-9_-]{40,})');
  static final RegExp _bareKey = RegExp(r'^([A-Za-z0-9_-]{43})$');

  /// Достаёт ключ из ссылки с `#k=…` или принимает сам ключ.
  static String? extractKey(String text) {
    final value = text.trim();
    final inLink = _keyInLink.firstMatch(value);
    if (inLink != null) return inLink.group(1);
    final bare = _bareKey.firstMatch(value);
    return bare?.group(1);
  }

  // ---- Базовые операции ----

  static Future<Uint8List> _seal(Uint8List key, List<int> plain, List<int> aad) async {
    final box = await _gcm.encrypt(plain, secretKey: SecretKey(key), aad: aad);
    return Uint8List.fromList(box.concatenation());
  }

  static Future<Uint8List> _open(Uint8List key, List<int> data, List<int> aad) async {
    if (data.length < overhead) throw E2eeException('Данные повреждены');
    try {
      final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
      final clear = await _gcm.decrypt(box, secretKey: SecretKey(key), aad: aad);
      return Uint8List.fromList(clear);
    } catch (_) {
      throw E2eeException('Неверный ключ или файл повреждён');
    }
  }

  static List<int> get _aadName => utf8.encode('$_label|name');
  static List<int> get _aadCheck => utf8.encode('$_label|check');
  static List<int> _aadChunk(int index, int total, String fileId) =>
      utf8.encode('$_label|c|$index|$total|$fileId');

  // ---- Проверочная запись ----

  static Future<String> makeCheck(Uint8List key) async {
    return _b64u(await _seal(key, utf8.encode(_label), _aadCheck));
  }

  static Future<bool> verifyCheck(Uint8List key, String check) async {
    try {
      final plain = await _open(key, _unb64u(check), _aadCheck);
      return utf8.decode(plain) == _label;
    } catch (_) {
      return false;
    }
  }

  // ---- Имена ----

  /// Обрезает имя до 80 байт, сохраняя расширение: токен имени должен уместиться в лимит сервера.
  static String clampName(String name, {int maxBytes = _nameMaxBytes}) {
    final value = name.isEmpty ? 'file' : name;
    if (utf8.encode(value).length <= maxBytes) return value;
    final dot = value.lastIndexOf('.');
    final ext = dot > 0 && value.length - dot <= 12 ? value.substring(dot) : '';
    final base = ext.isNotEmpty ? value.substring(0, dot) : value;
    final chars = base.runes.toList();
    while (chars.isNotEmpty && utf8.encode(String.fromCharCodes(chars) + ext).length > maxBytes) {
      chars.removeLast();
    }
    final head = String.fromCharCodes(chars);
    return (head.isEmpty ? 'file' : head) + ext;
  }

  static Future<String> encryptName(Uint8List key, String name, int chunkSize) async {
    final payload = utf8.encode(jsonEncode({'n': clampName(name), 'c': chunkSize}));
    return namePrefix + _b64u(await _seal(key, payload, _aadName));
  }

  /// null, если это не токен или ключ не подходит.
  static Future<E2eeName?> decryptName(Uint8List key, String token) async {
    if (!isEncryptedName(token)) return null;
    try {
      final plain = await _open(key, _unb64u(token.substring(namePrefix.length)), _aadName);
      final data = jsonDecode(utf8.decode(plain));
      if (data is! Map) return null;
      final name = data['n'];
      final chunk = data['c'];
      if (name is! String || chunk is! int || chunk <= overhead) return null;
      return E2eeName(name, chunk);
    } catch (_) {
      return null;
    }
  }

  // ---- Размеры ----

  static int plainChunkSize(int chunkSize) => chunkSize - overhead;

  static int chunkCount(int plainSize, int chunkSize) {
    final per = plainChunkSize(chunkSize);
    final count = (plainSize + per - 1) ~/ per;
    return count < 1 ? 1 : count;
  }

  static int encryptedSize(int plainSize, int chunkSize) =>
      plainSize + overhead * chunkCount(plainSize, chunkSize);

  static int plainSize(int encryptedSize, int chunkSize) {
    final count = (encryptedSize + chunkSize - 1) ~/ chunkSize;
    final size = encryptedSize - overhead * count;
    return size < 0 ? 0 : size;
  }

  // ---- Куски ----

  static Future<Uint8List> encryptChunk(
    Uint8List key,
    List<int> plain,
    int index,
    int total,
    String fileId,
  ) {
    return _seal(key, plain, _aadChunk(index, total, fileId));
  }

  static Future<Uint8List> decryptChunk(
    Uint8List key,
    Uint8List encrypted,
    int index,
    int total,
    String fileId,
  ) {
    return _open(key, encrypted, _aadChunk(index, total, fileId));
  }

  /// Шифрует кусок в отдельном изоляте: 8 МБ AES на Dart не должны подвешивать интерфейс.
  static Future<Uint8List> encryptChunkInIsolate(
    Uint8List key,
    Uint8List plain,
    int index,
    int total,
    String fileId,
  ) {
    return Isolate.run(() => encryptChunk(key, plain, index, total, fileId));
  }

  /// Расшифровывает файл целиком (по одному куску в памяти) в отдельном изоляте.
  /// При ошибке недописанный [target] удаляется.
  static Future<void> decryptFile({
    required String source,
    required String target,
    required Uint8List key,
    required String fileId,
    required int chunkSize,
  }) async {
    try {
      await Isolate.run(() => _decryptFile(source, target, key, fileId, chunkSize));
    } on E2eeException {
      await _deleteQuietly(target);
      rethrow;
    } catch (_) {
      await _deleteQuietly(target);
      throw E2eeException('Не удалось расшифровать файл');
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<Uint8List> _readExactly(RandomAccessFile file, int count) async {
    final builder = BytesBuilder(copy: false);
    while (builder.length < count) {
      final part = await file.read(count - builder.length);
      if (part.isEmpty) throw E2eeException('Файл получен не полностью');
      builder.add(part);
    }
    return builder.toBytes();
  }

  static Future<void> _decryptFile(
    String source,
    String target,
    Uint8List key,
    String fileId,
    int chunkSize,
  ) async {
    final input = await File(source).open();
    final output = await File(target).open(mode: FileMode.write);
    try {
      final total = await input.length();
      final count = (total + chunkSize - 1) ~/ chunkSize;
      if (count < 1) throw E2eeException('Файл пуст или повреждён');
      for (var index = 0; index < count; index++) {
        final need = index < count - 1 ? chunkSize : total - chunkSize * (count - 1);
        final encrypted = await _readExactly(input, need);
        final plain = await decryptChunk(key, encrypted, index, count, fileId);
        await output.writeFrom(plain);
      }
    } finally {
      await input.close();
      await output.close();
    }
  }
}
