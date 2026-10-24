import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmps/models/storage_file.dart';
import 'package:tmps/services/e2ee.dart';

// Векторы созданы сайтовой реализацией (site/node/static/js/.clear_js/e2ee.js) с ключом из байтов 0..31
// и независимо перепроверены Python-реализацией: приложение обязано расшифровывать то, что шифрует сайт.
const _key = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
const _chunkSize = 1024;
const _fileId = 'e2e1.vector-file';
const _plainLength = 1096;
const _total = 2;
const _check = 'WnxrhDqWZP1GTbuSbd1yTxwrXsHbvlgl4mTfZu91nbzvsfcmv3YJjg';
const _nameToken = 'e2e1.zlXhWoLl14L-ByUqTwCImH4z9wlbKY1QnSkkJipvt60-0JLYUEDm_pJgUTMTF14vWrORgi356ZgT7R6kZFFVCRDXFJjhqCos';
const _chunks = <String>[
    '53DiLd1_R13WCyeHcxl70H0UtaX6VQPFoStE_D2W8sXMQ_xW_W341K31Y3ifbu64oBp5V6iCVVnEObfhsw48NwKIcS76voRhqdZowXbx9Uf4ZMeRiWTERejCqg4_S-K2D-SSCw_puBAUpuklf-6mJgTwq9n1gEntNJTvZYPqxw4ppLpybytwL4hwLhSYtO2W26Ro8oT0hcn4YHicUn5qfZH6u4Iov0iSzzTqip8HwFO75FtQvRo4XuZ3zChWoE2FjUr-ipzD3vE_8ugnPf8ds_2jVldAa-oxi10lepJ9m53Ipf_MjKfhfo8ZwoFzrnFOefztZqWUzZCeGqswvQrzmSTVlBjlx-UWig2LSU7FBZzOxeFHJ6TINGz6LlTZkQ8j0nm2qH1VP2dsTbny7cXSOQ4FG79bsWga6GHgGx26A-LH1CIfxOGik5GvJjHlY4z7u1NvzMBq48RO0Y0P19A05J7iZJMrelLelk9ybErCR78oRcIgQ_PRcbe3i95AeYPZrH59ouoGpvH9WcsHG5zYiDmJ5CpyvPVP-3FbgqBxOFo88Y8tTKMRwHtNPI3wg08PXvaueLdosqCqGjN8qIyzi7Rl6lPT3yFxyogxPlVyrwAQczKeN0gSFp8UYrA05efEQ62h-0hNE94E488nqpuWTwF9scHCMfujmEMXz8fpjsulcLGRzXvcvDdFFEqQPa5ZuLFmhvllDPIOPggFSQdnXFx_K9KWcB_T9K2gooqSTMbHg5IS7ZatctV3uOZGrB2-SfWOREt-zjXEPkutrRMJIeJAWpAQjFTd99hAqsOzILplEikzxbDrkQEUKMtcQArLPpSIgjxE4m_MPImSqvMD05NPP6meyIvzHXVAkEbGvD-CnrRni_8-BS2_Y4lnKsgwGQhGaZYJy6BMwrEk4Yf61K7mFncPXVXi7NwvlVyoXHqoO3Y02Uq4dAZ2g1oOCmmnlH7o1r_0b_nTgo5QhT-iXw8BP6AVZDr6BCGVQXwsDSc3usO7XvMNxofUiieQIC1BbqBcegbwZz2rxr16AD1_59kasUR6WMthcTtwnCO_HSkYTZfB6jGuflWLob8m7C0X1j6dd40tXenI15W1_7jQJ8PqzUp-vBT9NZyos43UMYQKikZcczCRAjtDqdKqHdWD7hPjrN7lNy7iTsnUKq48QnbYP1yIQtDrZFl_aqAdmnmQkjkH4nYYaX41L4dY3tVkQh54_7n28P1gFv7LhuX0QPtCdFUsOOm_N_2-nTG67GMfjnEHhpxUSxUS-U2mykfCD0lI8txj5jtO44KsAxpQMOmzIfBh8nqxSTbMv5dHlGdBD4Tr7JVETFqC0HGnEotBQGE3w1MEsRp_CZkvwrM6Tg',
    'xmoCTaiZyu2pLUDk0mfJAvT3P_77bW4dqADXI1l2wVLhfWiSxzRMfZAmy14Q-R4apJ99DKhTwsORdj11h4bDlMcIS3tAB4BlVYFpwGOcwnVyYnJ1CzUmju26GF1hc9HFNnWF_GtIG5ZGujaoOtW_ltYY-YDIx5xb4BxM9IojESU',
];

Uint8List _unb64u(String text) => Uint8List.fromList(base64Url.decode(base64Url.normalize(text)));

void main() {
  final key = E2ee.keyBytes(_key);

  group('E2EE: совместимость с сайтом', () {
    test('проверочная запись с сайта подходит к ключу, к чужому ключу не подходит', () async {
      expect(await E2ee.verifyCheck(key, _check), isTrue);
      expect(await E2ee.verifyCheck(E2ee.keyBytes(E2ee.generateKey()), _check), isFalse);
      expect(await E2ee.verifyCheck(key, 'AAAA'), isFalse);
    });

    test('имя файла с сайта расшифровывается вместе с размером чанка', () async {
      final name = await E2ee.decryptName(key, _nameToken);
      expect(name, isNotNull);
      expect(name!.name, 'Отчёт 2026 🚀.pdf');
      expect(name.chunkSize, 8388608);
      expect(await E2ee.decryptName(E2ee.keyBytes(E2ee.generateKey()), _nameToken), isNull);
      expect(await E2ee.decryptName(key, 'plain.txt'), isNull);
    });

    test('куски файла с сайта расшифровываются и собираются в исходные данные', () async {
      final out = BytesBuilder();
      for (var i = 0; i < _chunks.length; i++) {
        out.add(await E2ee.decryptChunk(key, _unb64u(_chunks[i]), i, _total, _fileId));
      }
      final bytes = out.toBytes();
      expect(bytes.length, _plainLength);
      for (var i = 0; i < bytes.length; i++) {
        expect(bytes[i], (i * 7 + 3) & 255);
      }
    });

    test('куски привязаны к файлу, номеру и общему числу', () async {
      final first = _unb64u(_chunks[0]);
      await expectLater(E2ee.decryptChunk(key, first, 0, _total, 'e2e1.other'), throwsA(isA<E2eeException>()));
      await expectLater(E2ee.decryptChunk(key, first, 1, _total, _fileId), throwsA(isA<E2eeException>()));
      await expectLater(E2ee.decryptChunk(key, first, 0, _total + 1, _fileId), throwsA(isA<E2eeException>()));
      final tampered = Uint8List.fromList(first)..[100] ^= 1;
      await expectLater(E2ee.decryptChunk(key, tampered, 0, _total, _fileId), throwsA(isA<E2eeException>()));
    });
  });

  group('E2EE: размеры', () {
    test('совпадают с сайтом', () {
      expect(E2ee.encryptedSize(0, _chunkSize), 28);
      expect(E2ee.encryptedSize(_chunkSize - 28, _chunkSize), 1024);
      expect(E2ee.encryptedSize(_chunkSize - 28 + 1, _chunkSize), 1053);
      expect(E2ee.plainSize(E2ee.encryptedSize(_plainLength, _chunkSize), _chunkSize), 1096);
    });

    test('число кусков и обратное преобразование для границ', () {
      for (final size in [0, 1, 995, 996, 997, 2988, 3005, 50000]) {
        final enc = E2ee.encryptedSize(size, _chunkSize);
        expect(E2ee.plainSize(enc, _chunkSize), size, reason: 'size=$size');
        expect(E2ee.chunkCount(size, _chunkSize), (enc + _chunkSize - 1) ~/ _chunkSize, reason: 'size=$size');
      }
    });
  });

  group('E2EE: свои операции', () {
    test('имя шифруется туда и обратно, токен укладывается в лимит сервера', () async {
      final token = await E2ee.encryptName(key, 'я' * 300 + '.tar.gz', 8388608);
      expect(token.startsWith('e2e1.'), isTrue);
      expect(token.length, lessThan(200));
      expect(RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(token), isTrue);
      final back = await E2ee.decryptName(key, token);
      expect(back!.name.endsWith('.gz'), isTrue);
      expect(utf8.encode(back.name).length, lessThanOrEqualTo(80));
      expect(await E2ee.encryptName(key, 'a.txt', 1024) == await E2ee.encryptName(key, 'a.txt', 1024), isFalse);
    });

    test('кусок шифруется и расшифровывается, пустой файл тоже', () async {
      final data = Uint8List.fromList(List<int>.generate(500, (i) => i & 255));
      final enc = await E2ee.encryptChunk(key, data, 0, 1, _fileId);
      expect(enc.length, 500 + 28);
      expect(await E2ee.decryptChunk(key, enc, 0, 1, _fileId), data);
      final empty = await E2ee.encryptChunk(key, const <int>[], 0, 1, _fileId);
      expect(empty.length, 28);
      expect((await E2ee.decryptChunk(key, empty, 0, 1, _fileId)).length, 0);
    });

    test('ключ: генерация, разбор ссылки', () {
      final k = E2ee.generateKey();
      expect(k.length, 43);
      expect(E2ee.keyBytes(k).length, 32);
      expect(() => E2ee.keyBytes('short'), throwsA(isA<E2eeException>()));
      expect(E2ee.extractKey('https://tmps.epsiquad.com/Ab3x#k=$k'), k);
      expect(E2ee.extractKey(k), k);
      expect(E2ee.extractKey('https://tmps.epsiquad.com/Ab3x'), isNull);
    });
  });

  group('Тип файла по имени', () {
    test('kindForName', () {
      expect(kindForName('photo.JPG'), 'image');
      expect(kindForName('movie.mp4'), 'video');
      expect(kindForName('doc.pdf'), 'pdf');
      expect(kindForName('data.zip'), 'archive');
      expect(kindForName('noext'), 'other');
    });
  });
}
