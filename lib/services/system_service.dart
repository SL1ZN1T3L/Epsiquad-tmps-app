import 'package:flutter/services.dart';

class LinkTarget {
  const LinkTarget({
    required this.label,
    required this.packageName,
    required this.activityName,
    required this.icon,
  });

  final String label;
  final String packageName;
  final String activityName;
  final Uint8List icon;

  factory LinkTarget.fromMap(Map<Object?, Object?> map) {
    return LinkTarget(
      label: map['label'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      activityName: map['activityName'] as String? ?? '',
      icon: map['icon'] as Uint8List? ?? Uint8List(0),
    );
  }
}

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

  static Future<List<LinkTarget>> getLinkTargets(String url) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
            'getLinkTargets',
            {'url': url},
          ) ??
          const [];
      return result
          .whereType<Map<Object?, Object?>>()
          .map(LinkTarget.fromMap)
          .where((target) =>
              target.label.isNotEmpty &&
              target.packageName.isNotEmpty &&
              target.activityName.isNotEmpty &&
              target.icon.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> openLinkTarget(String url, LinkTarget target) async {
    try {
      return await _channel.invokeMethod<bool>('openLinkTarget', {
            'url': url,
            'packageName': target.packageName,
            'activityName': target.activityName,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
