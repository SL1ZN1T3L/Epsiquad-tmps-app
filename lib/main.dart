import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'messenger.dart';
import 'providers/app_provider.dart';
import 'screens/pin_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/storages_screen.dart';
import 'services/download_service.dart';
import 'theme.dart';
import 'widgets/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
  // Обработчик нажатия на уведомление о скачивании нужен с самого запуска:
  // по нему Android может поднять закрытое приложение.
  DownloadService.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: TmpsColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const TmpsApp());
}

class TmpsApp extends StatelessWidget {
  const TmpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider()..bootstrap(),
      child: MaterialApp(
        title: 'Temp Storage',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        navigatorKey: navigatorKey,
        builder: (context, child) => AppShell(child: child ?? const SizedBox.shrink()),
        theme: buildTheme(),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppProvider, AppStage>((p) => p.stage);
    switch (stage) {
      case AppStage.loading:
        return const SplashScreen();
      case AppStage.locked:
        return const PinScreen(mode: PinMode.unlock);
      case AppStage.pinSetup:
        return const PinScreen(mode: PinMode.create);
      case AppStage.signedOut:
        return const LoginScreen();
      case AppStage.ready:
        return const StoragesScreen();
    }
  }
}
