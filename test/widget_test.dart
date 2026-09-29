import 'package:flutter_test/flutter_test.dart';
import 'package:tmps/format.dart';
import 'package:tmps/models/config.dart';
import 'package:tmps/models/storage.dart';
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
}
