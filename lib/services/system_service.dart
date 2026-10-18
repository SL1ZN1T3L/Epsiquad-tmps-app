import 'package:flutter/services.dart';

/// Мелкие системные настройки окна Android.
class SystemService {
  static const _channel = MethodChannel('com.epsiquad.tmps/system');

  /// Ключ в SharedPreferences. Нативная часть читает его при запуске
  /// (с префиксом «flutter.»), чтобы скрыть превью сразу, до старта Dart.
  static const hideRecentsKey = 'tmps_hide_recents';

  /// Скрывает содержимое приложения в списке недавних.
  /// На Android 13 и новее скриншоты остаются доступными, на старых версиях
  /// система запрещает и их (FLAG_SECURE).
  static Future<void> setHideRecents(bool hide) async {
    try {
      await _channel.invokeMethod<void>('setHideRecents', {'hide': hide});
    } catch (_) {}
  }
}
