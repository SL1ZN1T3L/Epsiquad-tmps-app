import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../icons.dart';
import '../models/session.dart';
import '../providers/app_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/brand.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  Timer? _poll;
  TelegramLogin? _tgLogin;

  @override
  void dispose() {
    _poll?.cancel();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  void _fail(Object error) {
    setState(() {
      _error = error is ApiException ? error.message : 'Что-то пошло не так';
      _busy = false;
    });
  }

  Future<void> _submitPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppProvider>();
    try {
      final result = await app.loginWithPassword(_login.text.trim(), _password.text);
      await app.signIn(result);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _startTelegram() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppProvider>();
    try {
      final login = await app.telegramStart();
      if (!mounted) return;
      setState(() => _tgLogin = login);
      await launchUrl(Uri.parse(login.url), mode: LaunchMode.externalApplication);
      _startPolling(login);
    } catch (e) {
      _fail(e);
    }
  }

  void _startPolling(TelegramLogin login) {
    _poll?.cancel();
    final deadline = DateTime.now().add(Duration(seconds: login.expiresIn));
    _poll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        timer.cancel();
        setState(() {
          _tgLogin = null;
          _busy = false;
          _error = 'Время подтверждения истекло, попробуйте снова';
        });
        return;
      }
      final app = context.read<AppProvider>();
      try {
        final result = await app.telegramClaim(login);
        if (result == null) return;
        timer.cancel();
        await app.signIn(result);
      } catch (e) {
        timer.cancel();
        if (!mounted) return;
        setState(() => _tgLogin = null);
        _fail(e);
      }
    });
  }

  void _cancelTelegram() {
    _poll?.cancel();
    setState(() {
      _tgLogin = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final config = app.config;
    final waiting = _tgLogin != null;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: BrandMark(size: 58)),
              const SizedBox(height: 24),
              const Text(
                'Вход',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
              const SizedBox(height: 8),
              const Text(
                'Аккаунт создаётся на сайте или в боте. Здесь только вход.',
                textAlign: TextAlign.center,
                style: TextStyle(color: TmpsColors.muted, height: 1.45),
              ),
              const SizedBox(height: 28),
              if (waiting) _telegramWaiting() else _passwordForm(config?.telegramAvailable ?? false),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _errorBox(_error!),
              ],
              if (app.notice != null) ...[
                const SizedBox(height: 16),
                Text(
                  app.notice!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TmpsColors.warn),
                ),
              ],
              const SizedBox(height: 28),
              Center(
                child: Text(
                  config == null ? 'tmps' : 'tmps · сервер ${config.serverVersion}',
                  style: const TextStyle(color: TmpsColors.faint, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordForm(bool telegram) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _login,
            enabled: !_busy,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Логин'),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Введите логин' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            enabled: !_busy,
            obscureText: _hidePassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitPassword(),
            decoration: InputDecoration(
              labelText: 'Пароль',
              suffixIcon: IconButton(
                icon: TmpsIcon(_hidePassword ? Ico.eye : Ico.eyeOff),
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
              ),
            ),
            validator: (value) =>
                (value ?? '').length < 8 ? 'Пароль короче 8 символов' : null,
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _submitPassword,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Text('Войти'),
          ),
          if (telegram) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _startTelegram,
              icon: const TmpsIcon(Ico.telegram, color: TmpsColors.telegram, size: 20),
              label: const Text('Через Telegram'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _telegramWaiting() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TmpsColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TmpsColors.border),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: TmpsColors.telegram),
          ),
          const SizedBox(height: 18),
          const Text(
            'Подтвердите вход в боте',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Откройте бота и нажмите «Подтвердить». Окно закроется само.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TmpsColors.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => launchUrl(Uri.parse(_tgLogin!.url), mode: LaunchMode.externalApplication),
            child: const Text('Открыть бота ещё раз'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _cancelTelegram, child: const Text('Отмена')),
        ],
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1FFB4B6B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x4DFB4B6B)),
      ),
      child: Row(
        children: [
          const TmpsIcon(Ico.alert, color: TmpsColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: TmpsColors.danger))),
        ],
      ),
    );
  }
}
