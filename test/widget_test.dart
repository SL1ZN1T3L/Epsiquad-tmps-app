import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmps/format.dart';
import 'package:tmps/models/config.dart';
import 'package:tmps/models/storage.dart';
import 'package:tmps/services/api_client.dart';
import 'package:tmps/services/node_service.dart';
import 'package:tmps/services/update_service.dart';

void main() {
  group('Размеры', () {
    test('округление и единицы', () {
      expect(fmtSize(0), '0 Б');
      expect(fmtSize(999), '999 Б');
      expect(fmtSize(1024), '1 КБ');
      expect(fmtSize(1536), '1.5 КБ');
      expect(fmtSize(500 * 1024 * 1024), '500 МБ');
      expect(fmtSize(1024 * 1024 * 1024), '1 ГБ');
      expect(fmtSize(5 * 1024 * 1024 * 1024), '5 ГБ');
    });
  });

  group('Склонения', () {
    test('файлы', () {
      expect(plural(1, 'файл', 'файла', 'файлов'), 'файл');
      expect(plural(2, 'файл', 'файла', 'файлов'), 'файла');
      expect(plural(5, 'файл', 'файла', 'файлов'), 'файлов');
      expect(plural(11, 'файл', 'файла', 'файлов'), 'файлов');
      expect(plural(21, 'файл', 'файла', 'файлов'), 'файл');
    });

    test('сроки из тарифов', () {
      expect(fmtHours(3), '3 ч');
      expect(fmtHours(24), '1 день');
      expect(fmtHours(48), '2 дня');
      expect(fmtHours(7 * 24), '7 дней');
      expect(fmtHours(14 * 24), '14 дней');
    });
  });

  group('Версии', () {
    test('сравнение с суффиксами', () {
      expect(compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(compareVersions('1.2.0', '1.10.0'), lessThan(0));
      expect(compareVersions('1.0.0+20260928', '1.0.0'), 0);
      expect(compareVersions('2.0.0-beta', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.0', '1.0.0'), 0);
    });
  });

  group('Разбор ответов сервера', () {
    test('тариф из /api/v1/config', () {
      final plan = PlanInfo.fromJson(const {
        'id': 'basic05',
        'name': 'Мини',
        'description': '500 МБ, срок на выбор, продление до 14 дней',
        'quota_bytes': 524288000,
        'ttl_options': [1, 3, 10, 24, 48, 72],
        'max_lifetime_hours': 336,
        'extendable': true,
        'unlimited': false,
        'admin_only': false,
      });
      expect(plan.id, 'basic05');
      expect(plan.quotaBytes, 500 * 1024 * 1024);
      expect(plan.ttlOptions.length, 6);
      expect(plan.maxLifetimeHours, 14 * 24);
      expect(plan.extendable, isTrue);
    });

    test('хранилище без срока и с пустыми полями', () {
      final item = StorageItem.fromJson(const {
        'code': 'aB3x',
        'url': 'https://tmps.epsiquad.com/aB3x',
        'plan': 'admin10',
        'plan_name': 'Админ 10',
        'quota_bytes': 10737418240,
        'used_bytes': 0,
        'status': 'active',
      });
      expect(item.displayTitle, 'Хранилище aB3x');
      expect(item.unlimited, isTrue);
      expect(item.timeLeft, isNull);
      expect(item.canExtend, isFalse);
      expect(item.usedRatio, 0);
      expect(item.planOptions, isEmpty);
    });

    test('вариант смены тарифа', () {
      final option = PlanOption.fromJson(const {
        'plan': 'basic05',
        'plan_name': 'Мини',
        'quota_bytes': 524288000,
        'direction': 'down',
        'available': false,
        'reason': 'Занято 600 МБ - не поместится в 500 МБ',
      });
      expect(option.isUpgrade, isFalse);
      expect(option.available, isFalse);
      expect(option.reason, contains('не поместится'));
    });

    test('ключ владельца считается протухшим заранее', () {
      final fresh = OwnerGrant.fromJson(const {
        'token': 'payload.signature',
        'header': 'X-Tmps-Owner',
        'base_url': 'https://tmps.epsiquad.com/aB3x',
        'expires_in': 86400,
      });
      expect(fresh.stale, isFalse);

      final almostGone = OwnerGrant.fromJson(const {
        'token': 'payload.signature',
        'header': 'X-Tmps-Owner',
        'base_url': 'https://tmps.epsiquad.com/aB3x',
        'expires_in': 60,
      });
      expect(almostGone.stale, isTrue);
    });
  });

  group('API: безопасные повторы', () {
    test('POST после таймаута не отправляется повторно', () async {
      var calls = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('{"ok":true}', 200);
        }),
        accessToken: () => null,
        refresh: () async => false,
        baseUrl: 'https://example.test',
      );
      await expectLater(
        api.request(
          'POST',
          '/write',
          auth: false,
          timeout: const Duration(milliseconds: 5),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
      api.close();
    });

    test('GET после таймаута повторяется один раз', () async {
      var calls = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          calls++;
          if (calls == 1) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          return http.Response('{"ok":true}', 200);
        }),
        accessToken: () => null,
        refresh: () async => false,
        baseUrl: 'https://example.test',
      );
      final result = await api.request(
        'GET',
        '/read',
        auth: false,
        timeout: const Duration(milliseconds: 5),
      );
      expect(result['ok'], isTrue);
      expect(calls, 2);
      api.close();
    });

    test('только 401/403 завершают серверную сессию', () {
      expect(ApiException('network').invalidatesSession, isFalse);
      expect(ApiException('limited', status: 429).invalidatesSession, isFalse);
      expect(ApiException('down', status: 503).invalidatesSession, isFalse);
      expect(ApiException('expired', status: 401).invalidatesSession, isTrue);
      expect(ApiException('banned', status: 403).invalidatesSession, isTrue);
    });
  });

  group('API: OpenAPI discovery', () {
    test('авторизованные вызовы используют пути из схемы', () async {
      const operations = <String, List<String>>{
        'auth_logout': ['POST', '/custom/v9/auth/logout'],
        'me': ['GET', '/custom/v9/me'],
        'list_devices': ['GET', '/custom/v9/devices'],
        'drop_device': ['DELETE', '/custom/v9/devices/{device_pk}'],
        'list_plans': ['GET', '/custom/v9/plans'],
        'my_storages': ['GET', '/custom/v9/storages'],
        'create_storage': ['POST', '/custom/v9/storages'],
        'one_storage': ['GET', '/custom/v9/storages/{code}'],
        'storage_token': ['POST', '/custom/v9/storages/{code}/token'],
        'extend': ['POST', '/custom/v9/storages/{code}/extend'],
        'change_plan': ['POST', '/custom/v9/storages/{code}/plan'],
        'rename': ['PATCH', '/custom/v9/storages/{code}'],
        'set_access': ['PATCH', '/custom/v9/storages/{code}/access'],
        'set_password': ['POST', '/custom/v9/storages/{code}/password'],
        'rotate': ['POST', '/custom/v9/storages/{code}/rotate'],
        'delete_storage': ['DELETE', '/custom/v9/storages/{code}'],
      };
      final paths = <String, Map<String, dynamic>>{};
      for (final entry in operations.entries) {
        final methods = paths.putIfAbsent(
          entry.value[1],
          () => <String, dynamic>{},
        );
        methods[entry.value[0].toLowerCase()] = {
          'operationId': '${entry.key}_generated',
        };
      }
      var meCalls = 0;
      final api = ApiClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/openapi.json') {
            return http.Response(
              jsonEncode({'openapi': '3.1.0', 'paths': paths}),
              200,
            );
          }
          if (request.url.path == '/custom/v9/me') {
            meCalls++;
            return http.Response('{"ok":true}', 200);
          }
          return http.Response('{"error":"not found"}', 404);
        }),
        accessToken: () => 'access',
        refresh: () async => false,
        baseUrl: 'https://example.test',
      );
      await api.discover();
      await api.operation('me');
      expect(meCalls, 1);
      expect(api.eventsPath, '/custom/v9/ws');
      api.close();
    });

    test('node API использует base_url из owner grant', () async {
      late Uri requested;
      final node = NodeService(
        client: MockClient((request) async {
          requested = request.url;
          expect(request.headers['X-Tmps-Owner'], 'grant');
          return http.Response(
            '{"role":"owner","can_write":true,"files":[],"usage":{}}',
            200,
          );
        }),
      );
      final grant = OwnerGrant.fromJson(const {
        'token': 'grant',
        'header': 'X-Tmps-Owner',
        'base_url': 'https://node.example/root/Ab3x',
        'expires_in': 3600,
      });
      await node.state('ignored', grant);
      expect(requested.toString(), 'https://node.example/root/Ab3x/api/state');
      node.close();
    });
  });
}
