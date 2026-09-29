import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'providers/app_provider.dart';
import 'screens/lock_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/storages_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru');
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
        title: 'tmps',
        debugShowCheckedModeBanner: false,
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
        return const LockScreen();
      case AppStage.signedOut:
        return const LoginScreen();
      case AppStage.ready:
        return const StoragesScreen();
    }
  }
}
