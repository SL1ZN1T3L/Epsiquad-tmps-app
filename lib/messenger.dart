import 'package:flutter/material.dart';

/// Общий ключ для показа уведомлений вне дерева виджетов,
/// например после нажатия на уведомление о скачивании.
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Общий ключ навигатора: нужен, чтобы показать экран блокировки поверх
/// всего остального, не закрывая открытые экраны.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void showAppToast(String message) {
  final state = messengerKey.currentState;
  if (state == null) return;
  state
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
