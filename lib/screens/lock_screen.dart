import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import '../widgets/brand.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || context.read<AppProvider>().unlockFailed) return;
      _unlock();
    });
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    await context.read<AppProvider>().unlock();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BrandMark(size: 60),
              const SizedBox(height: 26),
              const Text(
                'Приложение заблокировано',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: TmpsColors.text),
              ),
              const SizedBox(height: 10),
              const Text(
                'Подтвердите личность, чтобы открыть хранилища',
                textAlign: TextAlign.center,
                style: TextStyle(color: TmpsColors.muted, height: 1.45),
              ),
              if (app.notice != null) ...[
                const SizedBox(height: 14),
                Text(
                  app.notice!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TmpsColors.warn),
                ),
              ],
              const SizedBox(height: 30),
              FilledButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: TmpsIcon(app.unlockFailed ? Ico.refresh : Ico.fingerprint),
                label: Text(app.unlockFailed ? 'Повторить' : 'Разблокировать'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : () => context.read<AppProvider>().signOut(),
                child: const Text('Войти в другой аккаунт'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
