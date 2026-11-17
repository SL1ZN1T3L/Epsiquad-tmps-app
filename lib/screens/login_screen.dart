import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../icons.dart';
import '../models/session.dart';
import '../providers/app_provider.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/system_service.dart';
import '../theme.dart';
import '../widgets/brand.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _totpCode = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _totpFormKey = GlobalKey<FormState>();

  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  String? _totpChallenge;
  Timer? _poll;
  Timer? _openTimer;
  DateTime? _telegramDeadline;
  TelegramLogin? _tgLogin;
  bool _claimInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final login = _tgLogin;
    if (login != null) _claimTelegram(login);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _openTimer?.cancel();
    _login.dispose();
    _password.dispose();
    _totpCode.dispose();
    super.dispose();
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error is ApiException ? error.message : 'Что-то пошло не так';
      _busy = false;
    });
  }

  Future<void> _retryConfig() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<AppProvider>().refreshConfig();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Настройки сервера недоступны';
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
      final result =
          await app.loginWithPassword(_login.text.trim(), _password.text);
      await app.signIn(result);
    } on TotpRequiredException catch (e) {
      _showTotp(e.challenge);
    } catch (e) {
      _fail(e);
    }
  }

  void _showTotp(String challenge) {
    if (!mounted) return;
    _poll?.cancel();
    _openTimer?.cancel();
    _totpCode.clear();
    setState(() {
      _totpChallenge = challenge;
      _tgLogin = null;
      _busy = false;
      _error = null;
    });
  }

  void _cancelTotp() {
    _totpCode.clear();
    setState(() {
      _totpChallenge = null;
      _busy = false;
      _error = null;
    });
  }

  Future<void> _submitTotp() async {
    if (!(_totpFormKey.currentState?.validate() ?? false)) return;
    final challenge = _totpChallenge;
    if (challenge == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppProvider>();
    try {
      final result =
          await app.loginWithTotp(challenge, _totpCode.text.trim());
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
      _openTimer?.cancel();
      setState(() => _tgLogin = login);
      _startPolling(login);
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _openTelegram(String url) async {
    final targets = await SystemService.getLinkTargets(url);
    if (!mounted) return;
    if (targets.isEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    final target = await showModalBottomSheet<LinkTarget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          decoration: BoxDecoration(
            color: TmpsColors.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: TmpsColors.border),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.65,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: TmpsColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Открыть бота',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Выберите приложение',
                      style: TextStyle(color: TmpsColors.muted),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: targets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = targets[index];
                      return ListTile(
                        onTap: () => Navigator.of(sheetContext).pop(item),
                        tileColor: TmpsColors.bg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.memory(
                            item.icon,
                            width: 46,
                            height: 46,
                            fit: BoxFit.contain,
                          ),
                        ),
                        title: Text(
                          item.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: const TmpsIcon(
                          Ico.external,
                          size: 18,
                          color: TmpsColors.muted,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (target != null) {
      await SystemService.openLinkTarget(url, target);
    }
  }

  Future<void> _copyTelegramCode() async {
    final login = _tgLogin;
    if (login == null || login.code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: login.code));
    if (!mounted || _tgLogin?.token != login.token) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Код скопирован'),
          duration: Duration(seconds: 2),
        ),
      );
    _openTimer?.cancel();
    _openTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || _tgLogin?.token != login.token) return;
      unawaited(_openTelegram(login.url));
    });
  }

  void _startPolling(TelegramLogin login) {
    _poll?.cancel();
    _telegramDeadline = DateTime.now().add(Duration(seconds: login.expiresIn));
    _poll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _claimTelegram(login),
    );
  }

  Future<void> _claimTelegram(TelegramLogin login) async {
    if (_claimInFlight || !mounted || _tgLogin?.token != login.token) return;
    final deadline = _telegramDeadline;
    if (deadline == null) return;
    if (DateTime.now().isAfter(deadline)) {
      _poll?.cancel();
      setState(() {
        _tgLogin = null;
        _busy = false;
        _error = 'Время подтверждения истекло, попробуйте снова';
      });
      return;
    }
    _claimInFlight = true;
    final app = context.read<AppProvider>();
    try {
      final result = await app.telegramClaim(login);
      if (!mounted || _tgLogin?.token != login.token) return;
      if (result == null) return;
      await app.signIn(result);
      _poll?.cancel();
    } on TotpRequiredException catch (e) {
      if (!mounted || _tgLogin?.token != login.token) return;
      _poll?.cancel();
      _showTotp(e.challenge);
    } on ApiException catch (e) {
      if (e.status == 0) return;
      if (!mounted || _tgLogin?.token != login.token) return;
      _poll?.cancel();
      setState(() => _tgLogin = null);
      _fail(e);
    } catch (e) {
      if (!mounted || _tgLogin?.token != login.token) return;
      _poll?.cancel();
      setState(() => _tgLogin = null);
      _fail(e);
    } finally {
      _claimInFlight = false;
    }
  }

  void _cancelTelegram() {
    _poll?.cancel();
    _openTimer?.cancel();
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
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8),
              ),
              const SizedBox(height: 8),
              const Text(
                'Аккаунт создаётся на сайте или в боте. Здесь только вход.',
                textAlign: TextAlign.center,
                style: TextStyle(color: TmpsColors.muted, height: 1.45),
              ),
              const SizedBox(height: 28),
              if (_totpChallenge != null)
                _totpForm()
              else if (waiting)
                _telegramWaiting()
              else
                _passwordForm(config?.telegramAvailable ?? false),
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
              if (config == null)
                TextButton.icon(
                  onPressed: _busy ? null : _retryConfig,
                  icon: const TmpsIcon(Ico.refresh, size: 18),
                  label: const Text('Повторить получение настроек'),
                ),
              const SizedBox(height: 28),
              Center(
                child: Text(
                  config == null
                      ? 'tmps'
                      : 'tmps · сервер ${config.serverVersion}',
                  style:
                      const TextStyle(color: TmpsColors.faint, fontSize: 12.5),
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
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                  )
                : const Text('Войти'),
          ),
          if (telegram) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _startTelegram,
              icon: const TmpsIcon(Ico.telegram,
                  color: TmpsColors.telegram, size: 20),
              label: const Text('Через Telegram'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totpForm() {
    return Form(
      key: _totpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Двухфакторная аутентификация',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'Введите текущий код из приложения или один неиспользованный резервный код.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TmpsColors.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _totpCode,
            enabled: !_busy,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 64,
            onFieldSubmitted: (_) => _submitTotp(),
            decoration: const InputDecoration(
              labelText: 'Код подтверждения',
              hintText: '123456 или XXXXX-XXXXX',
              counterText: '',
            ),
            validator: (value) {
              final length = (value ?? '').trim().length;
              if (length < 6) return 'Введите код подтверждения';
              return null;
            },
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _submitTotp,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                  )
                : const Text('Подтвердить вход'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _cancelTotp,
            child: const Text('Вернуться ко входу'),
          ),
        ],
      ),
    );
  }

  Widget _telegramWaiting() {
    final login = _tgLogin!;
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
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: TmpsColors.telegram),
          ),
          const SizedBox(height: 18),
          Text(
            login.code.isEmpty
                ? 'Подтвердите вход в боте'
                : 'Отправьте боту код',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          if (login.code.isNotEmpty) ...[
            const SizedBox(height: 14),
            SelectableText(
              login.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TmpsColors.telegram,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _copyTelegramCode,
              icon: const TmpsIcon(Ico.copy, size: 18),
              label: const Text('Скопировать код'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            login.code.isEmpty
                ? 'Откройте бота и нажмите «Подтвердить». Окно закроется само.'
                : 'Откройте бота, отправьте этот код одним сообщением, проверьте запрос и нажмите «Подтвердить». Окно закроется само.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: TmpsColors.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => _openTelegram(login.url),
            child: Text(
              login.code.isEmpty ? 'Открыть бота' : 'Открыть бота ещё раз',
            ),
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
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: TmpsColors.danger))),
        ],
      ),
    );
  }
}
