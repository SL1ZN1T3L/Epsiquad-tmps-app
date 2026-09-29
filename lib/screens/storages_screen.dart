import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../icons.dart';
import '../models/config.dart';
import '../models/storage.dart';
import '../providers/app_provider.dart';
import '../providers/storages_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/storage_card.dart';
import 'settings_screen.dart';
import 'storage_screen.dart';

class StoragesScreen extends StatelessWidget {
  const StoragesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return ChangeNotifierProvider(
      create: (_) => StoragesProvider(app.storages)..load(),
      child: const _StoragesView(),
    );
  }
}

class _StoragesView extends StatelessWidget {
  const _StoragesView();

  Future<void> _create(BuildContext context) async {
    final app = context.read<AppProvider>();
    final provider = context.read<StoragesProvider>();
    final config = app.config;
    if (config == null) {
      _toast(context, 'Настройки сервера ещё не получены');
      return;
    }
    final plans = config.plans;
    if (plans.isEmpty) {
      _toast(context, 'Сервер не прислал ни одного тарифа');
      return;
    }
    final request = await showModalBottomSheet<_CreateRequest>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateSheet(plans: plans),
    );
    if (request == null || !context.mounted) return;
    try {
      final item = await provider.create(
        plan: request.plan,
        ttlHours: request.ttlHours,
        title: request.title,
      );
      if (!context.mounted) return;
      _toast(context, 'Хранилище ${item.code} создано');
    } on ApiException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final provider = context.watch<StoragesProvider>();
    final items = provider.items;
    final limit = app.config?.userMaxActive ?? 3;
    final admin = app.user?.isAdmin ?? false;
    final canCreate = admin || items.length < limit;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          children: [
            BrandMark(size: 30, withText: false),
            SizedBox(width: 10),
            Text('Хранилища'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Настройки',
            icon: const TmpsIcon(Ico.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _create(context),
              backgroundColor: TmpsColors.accent,
              foregroundColor: Colors.white,
              icon: const TmpsIcon(Ico.plus),
              label: const Text('Создать'),
            )
          : null,
      body: RefreshIndicator(
        color: TmpsColors.accent,
        backgroundColor: TmpsColors.surface,
        onRefresh: () => provider.load(silent: true),
        child: _body(context, app, provider, items, limit, admin),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppProvider app,
    StoragesProvider provider,
    List<StorageItem> items,
    int limit,
    bool admin,
  ) {
    if (provider.loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: TmpsColors.accent));
    }
    if (provider.error != null && items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Ico.cloudOff,
            title: 'Не удалось загрузить',
            subtitle: provider.error,
            action: FilledButton(
              onPressed: () => provider.load(),
              child: const Text('Повторить'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (app.outdated) _updateBanner(context, app, required: true),
        if (!app.outdated && app.update != null) _updateBanner(context, app, required: false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            admin
                ? 'Активных хранилищ: ${items.length}'
                : '${items.length} из $limit активных хранилищ',
            style: const TextStyle(color: TmpsColors.muted),
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: EmptyState(
              icon: Ico.box,
              title: 'Пока пусто',
              subtitle: 'Создайте хранилище, загрузите файлы и отправьте короткую ссылку.',
            ),
          ),
        for (final item in items) ...[
          StorageCard(
            item: item,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StorageScreen(item: item, storages: provider),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _updateBanner(BuildContext context, AppProvider app, {required bool required}) {
    final release = app.update;
    final color = required ? TmpsColors.danger : TmpsColors.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TmpsColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          TmpsIcon(required ? Ico.warning : Ico.download, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  required ? 'Нужно обновить приложение' : 'Вышла новая версия',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  required
                      ? 'Сервер больше не поддерживает эту версию'
                      : 'Версия ${release?.version ?? ''} доступна на GitHub',
                  style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (release != null)
            TextButton(
              onPressed: () => launchUrl(Uri.parse(release.pageUrl), mode: LaunchMode.externalApplication),
              child: const Text('Открыть'),
            ),
        ],
      ),
    );
  }
}

class _CreateRequest {
  const _CreateRequest({required this.plan, this.ttlHours, this.title});

  final String plan;
  final int? ttlHours;
  final String? title;
}

class _CreateSheet extends StatefulWidget {
  const _CreateSheet({required this.plans});

  final List<PlanInfo> plans;

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  late PlanInfo _plan = widget.plans.first;
  int? _ttl;
  final _title = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ttl = _plan.ttlOptions.isNotEmpty ? _plan.ttlOptions.first : null;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _pick(PlanInfo plan) {
    setState(() {
      _plan = plan;
      _ttl = plan.ttlOptions.isNotEmpty ? plan.ttlOptions.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: TmpsColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Новое хранилище',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            const Text('Тариф', style: TextStyle(color: TmpsColors.muted, fontSize: 13)),
            const SizedBox(height: 8),
            for (final plan in widget.plans) ...[
              _PlanTile(
                plan: plan,
                selected: plan.id == _plan.id,
                onTap: () => _pick(plan),
              ),
              const SizedBox(height: 8),
            ],
            if (_plan.ttlOptions.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Срок хранения', style: TextStyle(color: TmpsColors.muted, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hours in _plan.ttlOptions)
                    ChoiceChip(
                      label: Text(hours < 24 ? '$hours ч' : _daysLabel(hours)),
                      selected: _ttl == hours,
                      onSelected: (_) => setState(() => _ttl = hours),
                      backgroundColor: TmpsColors.surface2,
                      selectedColor: TmpsColors.accent,
                      labelStyle: TextStyle(
                        color: _ttl == hours ? Colors.white : TmpsColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                      side: const BorderSide(color: TmpsColors.border),
                    ),
                ],
              ),
              if (_plan.maxLifetimeHours != null) ...[
                const SizedBox(height: 10),
                Text(
                  _plan.extendable
                      ? 'Продлить можно позже, суммарно до ${_hoursLabel(_plan.maxLifetimeHours!)} с момента создания.'
                      : 'Этот тариф не продлевается.',
                  style: const TextStyle(color: TmpsColors.faint, fontSize: 12.5, height: 1.4),
                ),
              ],
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _title,
              maxLength: 64,
              decoration: const InputDecoration(
                labelText: 'Название, необязательно',
                counterText: '',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _CreateRequest(plan: _plan.id, ttlHours: _ttl, title: _title.text),
              ),
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  static String _daysLabel(int hours) {
    final days = hours ~/ 24;
    if (hours % 24 != 0) return '$hours ч';
    return '$days ${_plural(days, 'день', 'дня', 'дней')}';
  }

  static String _hoursLabel(int hours) {
    if (hours % 24 == 0) {
      final days = hours ~/ 24;
      return '$days ${_plural(days, 'день', 'дня', 'дней')}';
    }
    return '$hours ч';
  }

  static String _plural(int n, String one, String few, String many) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.selected, required this.onTap});

  final PlanInfo plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0x247C6CFF) : TmpsColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? TmpsColors.accent : TmpsColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(plan.name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      if (plan.adminOnly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x2622D3EE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'админ',
                            style: TextStyle(
                              color: TmpsColors.accent2,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    plan.description,
                    style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _short(plan.quotaBytes),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.5),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(int bytes) {
    const gib = 1024 * 1024 * 1024;
    const mib = 1024 * 1024;
    if (bytes >= gib) {
      final value = bytes / gib;
      final text = value == value.roundToDouble() ? value.round().toString() : value.toStringAsFixed(1);
      return '$text ГБ';
    }
    return '${(bytes / mib).round()} МБ';
  }
}
