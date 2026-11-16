import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmps/models/storage.dart';
import 'package:tmps/providers/app_provider.dart';
import 'package:tmps/providers/storage_provider.dart';
import 'package:tmps/providers/storages_provider.dart';
import 'package:tmps/services/api_client.dart';
import 'package:tmps/services/node_service.dart';
import 'package:tmps/services/secure_store.dart';
import 'package:tmps/services/share_inbox.dart';
import 'package:tmps/services/storage_service.dart';
import 'package:tmps/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const reminderChannel = MethodChannel('com.epsiquad.tmps/reminders');
  const downloaderChannel = MethodChannel('com.bbflight.background_downloader');
  const downloaderBackgroundChannel =
      MethodChannel('com.bbflight.background_downloader.background');
  final secureValues = <String, String>{};

  Future<dynamic> secureHandler(MethodCall call) async {
    final key = call.arguments is Map ? (call.arguments as Map)['key'] : null;
    switch (call.method) {
      case 'read':
        return secureValues[key];
      case 'readAll':
        return Map<String, String>.from(secureValues);
      case 'write':
        secureValues[key] = (call.arguments as Map)['value'] as String;
        return null;
      case 'delete':
        secureValues.remove(key);
        return null;
      case 'deleteAll':
        secureValues.clear();
        return null;
      default:
        return null;
    }
  }

  setUp(() {
    secureValues.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, secureHandler);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reminderChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloaderChannel, (call) async {
      return switch (call.method) {
        'cancelAll' => true,
        'allTasks' => <dynamic>[],
        'popStatusUpdates' || 'popProgressUpdates' => <dynamic>[],
        _ => null,
      };
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            downloaderBackgroundChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reminderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloaderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(downloaderBackgroundChannel, null);
  });

  group('Защищённые метаданные', () {
    test('rotate переносит ключ, uploads и downloads на новый код', () async {
      final store = SecureStore();
      await store.writeE2eeKey('old', 'secret');
      await store.writeUploadTasks('old', [
        {'id': 'u1', 'path': '/private/file', 'uid': 'upload-1'},
      ]);
      await store.writeDownloadRecord('d1', {
        'taskId': 'd1',
        'storageCode': 'old',
        'displayName': 'file.txt',
      });

      await store.moveStorageData('old', 'new');

      expect(await store.readE2eeKey('old'), isNull);
      expect(await store.readE2eeKey('new'), 'secret');
      expect(await store.readUploadTasks('old'), isEmpty);
      expect((await store.readUploadTasks('new')).single['uid'], 'upload-1');
      expect((await store.readDownloadRecord('d1'))?['storageCode'], 'new');
    });

    test('wipe удаляет ключи и обе очереди передач', () async {
      final store = SecureStore();
      await store.writeE2eeKey('one', 'secret');
      await store.writeUploadTasks('one', [
        {'id': 'u1'},
      ]);
      await store.writeDownloadRecord('d1', {'taskId': 'd1'});

      await store.wipe();

      expect(await store.hasE2eeKeys(), isFalse);
      expect(await store.readUploadTasks('one'), isEmpty);
      expect(await store.readDownloadRecords(), isEmpty);
    });
  });

  group('Очередь «Поделиться»', () {
    test('отмена не удаляет файлы, а retry разрешает повторный выбор', () {
      final app = AppProvider();
      const file = SharedFile(name: 'a.txt', size: 3, path: '/cache/a.txt');
      app.acceptShare(const [file]);
      app.deferShare();

      expect(app.pendingShare, const [file]);
      expect(app.shareDeferred, isTrue);
      app.retryShare();
      expect(app.pendingShare, const [file]);
      expect(app.shareDeferred, isFalse);
      app.dispose();
    });

    test('completeShare удаляет только фактически поставленные файлы', () {
      final app = AppProvider();
      const first = SharedFile(name: 'a.txt', size: 3, path: '/cache/a.txt');
      const second = SharedFile(name: 'b.txt', size: 5, path: '/cache/b.txt');
      app.acceptShare(const [first]);
      app.deferShare();
      app.acceptShare(const [second]);
      app.completeShare(const [first]);

      expect(app.pendingShare, const [second]);
      expect(app.shareDeferred, isFalse);
      app.completeShare(const [second]);
      expect(app.pendingShare, isEmpty);
      app.dispose();
    });
  });

  group('StoragesProvider', () {
    test('устаревший ответ list не перезаписывает более новый', () async {
      var calls = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/openapi.json') {
            return http.Response(jsonEncode(openApiSchema()), 200);
          }
          calls++;
          final current = calls;
          if (current == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          return http.Response(
              jsonEncode({
                'storages': [storageJson(current == 1 ? 'old' : 'new')],
              }),
              200);
        }),
        accessToken: () => null,
        refresh: () async => false,
        baseUrl: 'https://example.test',
      );
      await api.discover();
      final provider = StoragesProvider(StorageService(api));
      final first = provider.load();
      final second = provider.load();
      await Future.wait([first, second]);

      expect(provider.items.single.code, 'new');
      provider.dispose();
      api.close();
    });

    test('rotate сохраняет E2EE-ключ даже при смене кода', () async {
      final store = SecureStore();
      await store.writeE2eeKey('old', 'secret');
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/openapi.json') {
            return http.Response(jsonEncode(openApiSchema()), 200);
          }
          expect(request.url.path, '/api/v1/storages/old/rotate');
          return http.Response(
            jsonEncode({'storage': storageJson('new')}),
            200,
          );
        }),
        accessToken: () => null,
        refresh: () async => false,
        baseUrl: 'https://example.test',
      );
      await api.discover();
      final provider = StoragesProvider(StorageService(api), secure: store);
      final item = await provider.rotate('old');

      expect(item.code, 'new');
      expect(provider.items.single.code, 'new');
      expect(await store.readE2eeKey('old'), isNull);
      expect(await store.readE2eeKey('new'), 'secret');
      provider.dispose();
      api.close();
    });
  });

  group('Восстановление upload', () {
    test('complete сохраняет неопределённость и не создаёт дубликат', () async {
      final store = SecureStore();
      final dir = await Directory.systemTemp.createTemp('tmps-upload-test');
      final file = File('${dir.path}/a.txt');
      await file.writeAsString('abc');
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/openapi.json') {
            return http.Response(jsonEncode(openApiSchema()), 200);
          }
          if (request.url.path == '/api/v1/storages/old/token') {
            return http.Response(
              jsonEncode({
                'token': 'owner',
                'header': 'X-Tmps-Owner',
                'base_url': 'https://node.test',
                'expires_in': 3600,
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/storages/old') {
            return http.Response(
                jsonEncode({'storage': storageJson('old')}), 200);
          }
          return http.Response('{"error":"not found"}', 404);
        }),
        accessToken: () => null,
        refresh: () async => false,
        baseUrl: 'https://example.test',
      );
      await api.discover();
      var initCalls = 0;
      var completeCalls = 0;
      var completedOnServer = false;
      final node = NodeService(
        client: MockClient((request) async {
          if (request.url.path == '/api/upload') {
            initCalls++;
            return http.Response(
              jsonEncode({
                'uid': 'uid-1',
                'name': 'a.txt',
                'chunk_size': 4,
                'total_chunks': 1,
                'received': <int>[],
              }),
              200,
            );
          }
          if (request.url.path == '/api/upload/uid-1/0') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/upload/uid-1' &&
              request.method == 'GET') {
            return http.Response('{"error":"not found"}', 404);
          }
          if (request.url.path == '/api/upload/uid-1/complete') {
            completeCalls++;
            final saved = await store.readUploadTasks('old');
            expect(saved.single['completionUncertain'], isTrue);
            expect(saved.single['uid'], 'uid-1');
            completedOnServer = true;
            return http.Response('{"error":"connection lost"}', 500);
          }
          if (request.url.path == '/api/state') {
            return http.Response(
              jsonEncode({
                'files': [
                  if (completedOnServer)
                    {'name': 'a.txt', 'size': 3, 'mtime': 1},
                ],
              }),
              200,
            );
          }
          return http.Response('{"error":"not found"}', 404);
        }),
      );
      final provider = StorageProvider(
        storages: StorageService(api),
        node: node,
        initial: StorageItem.fromJson(storageJson('old')),
        secure: store,
      );
      provider.enqueue([
        UploadSource(
          name: 'a.txt',
          size: 3,
          path: file.path,
          openStream: file.openRead,
        ),
      ]);
      await waitUntil(() =>
          provider.uploads.isNotEmpty &&
          provider.uploads.single.status == UploadStatus.error);
      final task = provider.uploads.single;
      expect(task.completionUncertain, isTrue);
      expect(initCalls, 1);
      expect(completeCalls, 1);

      provider.resume(task);
      await waitUntil(() => task.status == UploadStatus.done);
      expect(task.error, isNull);
      expect(initCalls, 1);
      expect(completeCalls, 1);
      await waitUntilAsync(
          () async => (await store.readUploadTasks('old')).isEmpty);
      provider.dispose();
      api.close();
      await dir.delete(recursive: true);
    });
  });

  group('Выход и обновления', () {
    test('signOut выключает Dev Mode и очищает состояние', () async {
      final app = AppProvider();
      await app.setDevMode(true);
      await app.signOut();

      expect(app.devMode, isFalse);
      expect(app.stage, AppStage.signedOut);
      expect(app.pendingShare, isEmpty);
      expect(app.update, isNull);
      app.dispose();
    });

    test('ошибка GitHub не маскируется под отсутствие обновления', () async {
      final service = UpdateService(
        client: MockClient((request) async => http.Response('limited', 403)),
      );
      await expectLater(
        service.latest(
          repoUrl: 'https://github.com/owner/repo',
          currentVersion: '1.0.0',
        ),
        throwsA(isA<UpdateFailure>()),
      );
      service.close();
    });
  });
}

Future<void> waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Условие не выполнено за отведённое время');
}

Future<void> waitUntilAsync(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Асинхронное условие не выполнено за отведённое время');
}

Map<String, dynamic> openApiSchema() {
  const operations = <String, List<String>>{
    'auth_logout': ['POST', '/api/v1/auth/logout'],
    'me': ['GET', '/api/v1/me'],
    'list_devices': ['GET', '/api/v1/devices'],
    'drop_device': ['DELETE', '/api/v1/devices/{device_pk}'],
    'list_plans': ['GET', '/api/v1/plans'],
    'my_storages': ['GET', '/api/v1/storages'],
    'create_storage': ['POST', '/api/v1/storages'],
    'one_storage': ['GET', '/api/v1/storages/{code}'],
    'storage_token': ['POST', '/api/v1/storages/{code}/token'],
    'extend': ['POST', '/api/v1/storages/{code}/extend'],
    'change_plan': ['POST', '/api/v1/storages/{code}/plan'],
    'rename': ['PATCH', '/api/v1/storages/{code}'],
    'set_access': ['PATCH', '/api/v1/storages/{code}/access'],
    'set_password': ['POST', '/api/v1/storages/{code}/password'],
    'rotate': ['POST', '/api/v1/storages/{code}/rotate'],
    'delete_storage': ['DELETE', '/api/v1/storages/{code}'],
  };
  final paths = <String, Map<String, dynamic>>{};
  for (final entry in operations.entries) {
    final methods = paths.putIfAbsent(
      entry.value[1],
      () => <String, dynamic>{},
    );
    methods[entry.value[0].toLowerCase()] = {
      'operationId': '${entry.key}_test',
    };
  }
  return {'openapi': '3.1.0', 'paths': paths};
}

Map<String, dynamic> storageJson(String code) => {
      'code': code,
      'url': 'https://example.test/$code',
      'plan': 'basic',
      'plan_name': 'Basic',
      'quota_bytes': 1024,
      'used_bytes': 0,
      'status': 'active',
    };
