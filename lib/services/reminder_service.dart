import 'package:flutter/services.dart';

import '../models/storage.dart';

/// Напоминания о скором окончании срока хранилища. Будильники ставит
/// нативная часть (AlarmManager), поэтому они сработают и при закрытом
/// приложении, и после перезагрузки телефона.
class ReminderService {
  static const _channel = MethodChannel('com.epsiquad.tmps/reminders');

  /// Пересоздаёт напоминания для списка хранилищ. [leadHours] равно нулю,
  /// если напоминания выключены.
  static Future<void> sync(List<StorageItem> items, {required int leadHours}) async {
    try {
      if (leadHours <= 0) {
        await _channel.invokeMethod<void>('cancelAll');
        return;
      }
      final now = DateTime.now();
      final payload = <Map<String, Object>>[
        for (final item in items)
          if (item.expiresAt != null && item.expiresAt!.isAfter(now))
            {
              'code': item.code,
              'title': item.displayTitle,
              'expiresAt': item.expiresAt!.millisecondsSinceEpoch,
            },
      ];
      await _channel.invokeMethod<void>('schedule', {
        'items': payload,
        'leadMs': leadHours * 3600 * 1000,
      });
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } catch (_) {}
  }
}
