import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../icons.dart';
import '../models/session.dart';
import '../providers/app_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<DeviceEntry>? _devices;
  String? _devicesError;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final list = await context.read<AppProvider>().devices();
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TmpsColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Отключить'),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          user?.login ?? (user?.tgUsername != null ? '@${user!.tgUsername}' : 'Telegram'),
                          style: const TextStyle(color: TmpsColors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (user?.isAdmin ?? false)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x1FFBBF24),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: const Color(0x4DFBBF24)),
                      ),
                      child: const Text('admin',
                          style: TextStyle(color: TmpsColors.warn, fontSize: 12, fontWeight: FontWeight.w600)),
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
                SwitchListTile(
                  value: app.biometricEnabled,
                  onChanged: app.biometricAvailable ? (value) => app.setBiometric(value) : null,
                  activeThumbColor: TmpsColors.accent,
                  title: const Text('Вход по биометрии'),
                  subtitle: Text(
                    app.biometricAvailable
                        ? 'Отпечаток или лицо при открытии приложения'
                        : 'На этом устройстве биометрия недоступна',
                    style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                  ),
                ),
              ],
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
                ListTile(
                  title: const Text('Версия приложения'),
                  trailing: Text(app.appVersion, style: const TextStyle(color: TmpsColors.muted)),
                ),
                ListTile(
                  title: const Text('Версия сервера'),
                  trailing: Text(config?.serverVersion ?? '-',
                      style: const TextStyle(color: TmpsColors.muted)),
                ),
                if (app.update != null)
                  ListTile(
                    leading: const TmpsIcon(Ico.download, color: TmpsColors.accent),
                    title: Text('Доступна версия ${app.update!.version}'),
                    subtitle: const Text('Открыть страницу релиза',
                        style: TextStyle(color: TmpsColors.muted, fontSize: 12.5)),
                    onTap: () => launchUrl(Uri.parse(app.update!.pageUrl),
                        mode: LaunchMode.externalApplication),
                  )
                else
                  ListTile(
                    title: const Text('Проверить обновления'),
                    trailing: const TmpsIcon(Ico.refresh, color: TmpsColors.muted),
                    onTap: () async {
                      await app.checkForUpdate();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(app.update == null
                            ? 'У вас последняя версия'
                            : 'Доступна версия ${app.update!.version}')),
                      );
                    },
                  ),
                if ((config?.publicUrl ?? '').isNotEmpty)
                  ListTile(
                    title: const Text('Открыть сайт'),
                    trailing: const TmpsIcon(Ico.external, color: TmpsColors.muted),
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
              if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const TmpsIcon(Ico.logout, color: TmpsColors.danger),
            label: const Text('Выйти', style: TextStyle(color: TmpsColors.danger)),
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
        subtitle: Text(_devicesError!, style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5)),
        trailing: IconButton(icon: const TmpsIcon(Ico.refresh), onPressed: _loadDevices),
      );
    }
    final devices = _devices;
    if (devices == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator(color: TmpsColors.accent)),
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
                Flexible(child: Text(device.name, overflow: TextOverflow.ellipsis)),
                if (device.current) ...[
                  const SizedBox(width: 8),
                  const Text('это устройство',
                      style: TextStyle(color: TmpsColors.accent, fontSize: 11.5)),
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
