import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../messenger.dart';
import '../providers/app_provider.dart';
import '../screens/pin_screen.dart';

/// Оболочка над навигатором: следит за бездействием и показывает экран
/// блокировки по таймеру поверх открытых экранов. Экраны под ним остаются
/// живыми, поэтому отправка и скачивание файлов не прерываются.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  Timer? _timer;
  Route<void>? _lockRoute;
  bool _wasReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<AppProvider>().checkAutoLock();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final app = context.read<AppProvider>();
    if (state == AppLifecycleState.paused) {
      // Отсчёт идёт с момента, когда приложение свернули.
      app.touch();
    } else if (state == AppLifecycleState.resumed) {
      app.checkAutoLock();
    }
  }

  void _reconcile() {
    if (!mounted) return;
    final app = context.read<AppProvider>();
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final ready = app.stage == AppStage.ready;
    final wantLock = app.autoLocked && ready;
    final route = _lockRoute;

    if (wantLock && route == null) {
      final created = PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondary) => const PopScope(
          canPop: false,
          child: PinScreen(mode: PinMode.relock),
        ),
      );
      _lockRoute = created;
      navigator.push(created);
    } else if (!wantLock && route != null) {
      _lockRoute = null;
      navigator.removeRoute(route);
    }

    // Вышли из аккаунта или стёрли данные при блокировке: убираем экраны,
    // открытые поверх стартового.
    if (_wasReady && !ready) navigator.popUntil((r) => r.isFirst);
    _wasReady = ready;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reconcile());
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => app.touch(),
      onPointerMove: (_) => app.touch(),
      child: widget.child,
    );
  }
}
