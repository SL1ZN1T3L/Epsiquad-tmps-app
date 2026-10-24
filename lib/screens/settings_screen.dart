import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../icons.dart';
import '../models/session.dart';
import '../providers/app_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import 'pin_screen.dart';
import '../widgets/update_dialog.dart';
import '../widgets/dialog_actions.dart';

Future<void> _changePin(BuildContext context, AppProvider app) async {
  final current = await askPin(context, 'Текущий пин-код');
  if (current == null || !context.mounted) return;
  final next = await askPin(context, 'Новый пин-код');
  if (next == null || !context.mounted) return;
  final again = await askPin(context, 'Повторите новый пин-код');
  if (again == null || !context.mounted) return;
  if (next != again) {
    _say(context, 'Пин-коды не совпали');
    return;
  }
  final error = await app.changePin(current, next);
  if (!context.mounted) return;
  _say(context, error ?? 'Пин-код изменён');
}

Future<void> _toggleBiometric(
    BuildContext context, AppProvider app, bool value) async {
  String? pin;
  if (value) {
    pin = await askPin(context, 'Подтвердите пин-кодом');
    if (pin == null || !context.mounted) return;
  }
  final error = await app.setBiometric(value, pin: pin);
  if (!context.mounted || error == null) return;
  _say(context, error);
}

String _autoLockLabel(int minutes) => minutes == 0
    ? 'Выключена'
    : 'Через $minutes ${plural(minutes, 'минуту', 'минуты', 'минут')}';

String _leadLabel(int hours) {
  switch (hours) {
    case 0:
      return 'Выключены';
    case 1:
      return 'За 1 час';
    case 6:
      return 'За 6 часов';
    case 24:
      return 'За сутки';
    default:
      return 'За ${fmtHours(hours)}';
  }
}

Future<T?> _pickValue<T>(
  BuildContext context,
  String title,
  List<T> options,
  String Function(T) label, {
  required T current,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final option in options)
            ListTile(
              title: Text(label(option)),
              trailing: option == current
                  ? const TmpsIcon(Ico.check, color: TmpsColors.accent)
                  : null,
              onTap: () => Navigator.of(ctx).pop(option),
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

Future<void> _pickAutoLock(BuildContext context, AppProvider app) async {
  final minutes = await _pickValue<int>(
    context,
    'Автоблокировка',
    const [0, 1, 5, 15, 30],
    _autoLockLabel,
    current: app.autoLockMinutes,
  );
  if (minutes != null) await app.setAutoLockMinutes(minutes);
}

Future<void> _pickLead(BuildContext context, AppProvider app) async {
  final hours = await _pickValue<int>(
    context,
    'Напоминание об истечении',
    const [0, 1, 6, 24, 72],
    _leadLabel,
    current: app.expiryLeadHours,
  );
  if (hours != null) await app.setExpiryLeadHours(hours);
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<DeviceEntry>? _devices;
  String? _devicesError;
  int _versionTaps = 0;
  DateTime? _lastVersionTap;
  StreamSubscription<String>? _events;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    // Вход или отключение устройства в другом клиенте: список устройств обновляется сам.
    _events = context.read<AppProvider>().events.listen((type) {
      if (type == 'devices') unawaited(_loadDevices());
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final app = context.read<AppProvider>();
      final list = await app.devices();
      if (!mounted) return;
      setState(() {
        _devices = list;
        _devicesError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _devicesError = e.message);
    }
  }

  Future<void> _revoke(DeviceEntry device) async {
    final app = context.read<AppProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Отключить «${device.name}»?'),
        content: Text(
          device.current
              ? 'Это текущее устройство. Приложение выйдет из аккаунта.'
              : 'Приложение на этом телефоне выйдет из аккаунта.',
          style: const TextStyle(color: TmpsColors.muted, height: 1.45),
        ),
        actions: [
          DialogActions(children: [
            TextButton(
              style: DialogActions.dangerStyle(ctx),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Отключить'),
            ),
            TextButton(
              style: DialogActions.dangerStyle(ctx),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
          ]),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await app.revokeDevice(device.id);
      if (device.current) {
        await app.signOut();
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      await _loadDevices();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _tapVersion(AppProvider app) async {
    final now = DateTime.now();
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTaps = 0;
    }
    _lastVersionTap = now;
    _versionTaps++;
    if (_versionTaps < 5) return;
    _versionTaps = 0;
    await app.setDevMode(!app.devMode);
    if (!mounted) return;
    _say(context,
        app.devMode ? 'Dev Mode включён, сеть отключена' : 'Dev Mode выключен');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final user = app.user;
    final config = app.config;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: TmpsColors.gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        (user?.displayName.isNotEmpty ?? false)
                            ? user!.displayName.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.displayName ?? 'Аккаунт',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          user?.login ??
                              (user?.tgUsername != null
                                  ? '@${user!.tgUsername}'
                                  : 'Telegram'),
                          style: const TextStyle(
                              color: TmpsColors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (user?.isAdmin ?? false)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x1FFBBF24),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: const Color(0x4DFBBF24)),
                      ),
                      child: const Text('admin',
                          style: TextStyle(
                              color: TmpsColors.warn,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _section('Безопасность'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const TmpsIcon(Ico.lock, color: TmpsColors.muted),
                  title: const Text('Изменить пин-код'),
                  subtitle: const Text('Основной способ входа',
                      style:
                          TextStyle(color: TmpsColors.muted, fontSize: 12.5)),
                  onTap: () => _changePin(context, app),
                ),
                ListTile(
                  leading: const TmpsIcon(Ico.clock, color: TmpsColors.muted),
                  title: const Text('Автоблокировка'),
                  subtitle: Text(
                    '${_autoLockLabel(app.autoLockMinutes)}. Блокирует приложение при бездействии и после сворачивания',
                    style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                  ),
                  onTap: () => _pickAutoLock(context, app),
                ),
                SwitchListTile(
                  value: app.hideRecents,
                  onChanged: app.setHideRecents,
                  activeThumbColor: TmpsColors.accent,
                  title: const Text('Скрывать окно в списке недавних'),
                  subtitle: const Text(
                    'Содержимое не видно в переключателе приложений. На Android 12 и ниже скриншоты тоже отключатся',
                    style: TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                  ),
                ),
                SwitchListTile(
                  value: app.biometricEnabled,
                  onChanged: app.biometricAvailable
                      ? (value) => _toggleBiometric(context, app, value)
                      : null,
                  activeThumbColor: TmpsColors.accent,
                  title: const Text('Вход по отпечатку'),
                  subtitle: Text(
                    app.biometricAvailable
                        ? 'Быстрее пин-кода. Пин-код продолжит работать всегда'
                        : 'На этом устройстве биометрия недоступна',
                    style: const TextStyle(
                        color: TmpsColors.muted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _section('Уведомления'),
          Card(
            child: ListTile(
              leading: const TmpsIcon(Ico.bell, color: TmpsColors.muted),
              title: const Text('Скоро истечёт срок хранилища'),
              subtitle: Text(
                '${_leadLabel(app.expiryLeadHours)}. Напомним, чтобы вы успели продлить хранилище или забрать файлы',
                style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
              ),
              onTap: () => _pickLead(context, app),
            ),
          ),
          const SizedBox(height: 16),
          _section('Устройства'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _devicesBody(),
            ),
          ),
          const SizedBox(height: 16),
          _section('О приложении'),
          Card(
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tapVersion(app),
                  onLongPress: () => _tapVersion(app),
                  child: ListTile(
                    title: const Text('Версия приложения'),
                    subtitle: app.devMode
                        ? const Text(
                            'DEV MODE · сеть отключена',
                            style: TextStyle(
                              color: TmpsColors.warn,
                              fontSize: 12.5,
                            ),
                          )
                        : null,
                    trailing: Text(
                      app.appVersion,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: TmpsColors.muted),
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Версия сервера'),
                  trailing: Text(
                    config?.serverVersion ?? '-',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: TmpsColors.muted),
                  ),
                ),
                if (app.update != null)
                  ListTile(
                    leading:
                        const TmpsIcon(Ico.download, color: TmpsColors.accent),
                    title: Text('Доступна версия ${app.update!.version}'),
                    subtitle: const Text('Скачать и установить',
                        style:
                            TextStyle(color: TmpsColors.muted, fontSize: 12.5)),
                    onTap: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          UpdateDialog(app: app, release: app.update!),
                    ),
                  )
                else
                  ListTile(
                    title: const Text('Проверить обновления'),
                    trailing:
                        const TmpsIcon(Ico.refresh, color: TmpsColors.muted),
                    onTap: () async {
                      await app.checkForUpdate();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(app.update == null
                                ? 'У вас последняя версия'
                                : 'Доступна версия ${app.update!.version}')),
                      );
                    },
                  ),
                if ((config?.publicUrl ?? '').isNotEmpty)
                  ListTile(
                    title: const Text('Открыть сайт'),
                    trailing:
                        const TmpsIcon(Ico.external, color: TmpsColors.muted),
                    onTap: () => launchUrl(Uri.parse(config!.publicUrl),
                        mode: LaunchMode.externalApplication),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () async {
              await app.signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            icon: const TmpsIcon(Ico.logout, color: TmpsColors.danger),
            label:
                const Text('Выйти', style: TextStyle(color: TmpsColors.danger)),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
            color: TmpsColors.faint,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          )),
    );
  }

  Widget _devicesBody() {
    if (_devicesError != null) {
      return ListTile(
        title: const Text('Не удалось загрузить устройства'),
        subtitle: Text(_devicesError!,
            style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5)),
        trailing: IconButton(
            icon: const TmpsIcon(Ico.refresh), onPressed: _loadDevices),
      );
    }
    final devices = _devices;
    if (devices == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child:
            Center(child: CircularProgressIndicator(color: TmpsColors.accent)),
      );
    }
    if (devices.isEmpty) {
      return const ListTile(title: Text('Активных устройств нет'));
    }
    return Column(
      children: [
        for (final device in devices)
          ListTile(
            leading: TmpsIcon(
              Ico.phone,
              color: device.current ? TmpsColors.accent : TmpsColors.muted,
            ),
            title: Row(
              children: [
                Flexible(
                    child: Text(device.name, overflow: TextOverflow.ellipsis)),
                if (device.current) ...[
                  const SizedBox(width: 8),
                  const Text('это устройство',
                      style:
                          TextStyle(color: TmpsColors.accent, fontSize: 11.5)),
                ],
              ],
            ),
            subtitle: Text(
              '${device.appVersion != null ? 'версия ${device.appVersion} · ' : ''}вход ${fmtDate(device.createdAt)} · активность ${fmtRelative(device.lastSeenAt)}',
              style: const TextStyle(color: TmpsColors.muted, fontSize: 12),
            ),
            trailing: IconButton(
              icon: const TmpsIcon(Ico.ban, color: TmpsColors.danger, size: 20),
              tooltip: 'Отключить',
              onPressed: () => _revoke(device),
            ),
          ),
      ],
    );
  }
}
