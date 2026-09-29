import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../icons.dart';
import '../models/storage.dart';
import '../providers/app_provider.dart';
import '../providers/storage_provider.dart';
import '../providers/storages_provider.dart';
import '../services/api_client.dart';
import '../services/node_service.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/download_panel.dart';
import '../widgets/file_tile.dart';
import '../widgets/upload_panel.dart';

class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key, required this.item, required this.storages});

  final StorageItem item;
  final StoragesProvider storages;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return ChangeNotifierProvider(
      create: (_) => StorageProvider(
        storages: app.storages,
        node: NodeService(),
        initial: item,
      )
        ..load()
        ..connect(),
      child: _StorageView(storages: storages),
    );
  }
}

class _StorageView extends StatelessWidget {
  const _StorageView({required this.storages});

  final StoragesProvider storages;

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickFiles(BuildContext context, StorageProvider provider) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;

    final sources = <UploadSource>[];
    var skipped = 0;
    for (final file in picked) {
      try {
        final size = file.lengthSync() ?? await file.length();
        if (size == null) {
          skipped++;
          continue;
        }
        sources.add(UploadSource(
          name: file.name,
          size: size,
          path: file.path,
          openStream: file.readAsByteStream,
        ));
      } catch (_) {
        skipped++;
      }
    }
    if (!context.mounted) return;
    if (sources.isEmpty) {
      _toast(context, 'Не удалось прочитать выбранные файлы');
      return;
    }
    if (skipped > 0) {
      _toast(context, 'Пропущено файлов: $skipped - не удалось определить размер');
    }
    final total = sources.fold<int>(0, (sum, f) => sum + f.size);
    if (total > provider.freeBytes) {
      _toast(context, 'Не хватает места: нужно ${fmtSize(total)}, свободно ${fmtSize(provider.freeBytes)}');
      return;
    }
    provider.enqueue(sources);
  }

  Future<void> _run(BuildContext context, Future<void> Function() action, String success) async {
    try {
      await action();
      if (context.mounted) _toast(context, success);
    } on ApiException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StorageProvider>();
    final item = provider.item;
    final state = provider.state;
    final canWrite = state?.canWrite ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.displayTitle, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            icon: const TmpsIcon(Ico.more),
            color: TmpsColors.bg2,
            onSelected: (value) => _onMenu(context, provider, value),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
              if (provider.files.isNotEmpty)
                const PopupMenuItem(value: 'zip', child: Text('Скачать всё архивом')),
              if (item.canExtend) const PopupMenuItem(value: 'extend', child: Text('Продлить')),
              if (item.planOptions.isNotEmpty)
                const PopupMenuItem(value: 'plan', child: Text('Сменить тариф')),
              const PopupMenuItem(value: 'access', child: Text('Доступ')),
              const PopupMenuItem(value: 'rotate', child: Text('Сменить ссылку')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Удалить хранилище', style: TextStyle(color: TmpsColors.danger)),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _pickFiles(context, provider),
              backgroundColor: TmpsColors.accent,
              foregroundColor: Colors.white,
              icon: const TmpsIcon(Ico.upload),
              label: const Text('Загрузить'),
            )
          : null,
      body: RefreshIndicator(
        color: TmpsColors.accent,
        backgroundColor: TmpsColors.surface,
        onRefresh: () => provider.load(silent: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _header(context, provider),
            const SizedBox(height: 12),
            UploadPanel(provider: provider),
            if (provider.uploads.isNotEmpty) const SizedBox(height: 12),
            DownloadPanel(provider: provider),
            if (provider.downloads.isNotEmpty) const SizedBox(height: 12),
            if (provider.error != null) ...[
              _errorBox(provider.error!),
              const SizedBox(height: 12),
            ],
            _filesHeader(provider),
            const SizedBox(height: 10),
            if (provider.loading && state == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: TmpsColors.accent)),
              )
            else if (provider.files.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: EmptyState(
                  icon: Ico.upload,
                  title: 'Файлов пока нет',
                  subtitle: 'Нажмите «Загрузить» и выберите что отправить.',
                ),
              )
            else
              for (final file in provider.files)
                FileTile(
                  file: file,
                  stats: state?.stats[file.name],
                  showStats: state?.isOwner ?? false,
                  canDelete: canWrite,
                  onShare: () => SharePlus.instance.share(
                    ShareParams(text: provider.fileUri(file).toString()),
                  ),
                  onDownload: () => unawaited(provider.download(file)),
                  onDelete: () => _confirmDeleteFile(context, provider, file.name),
                ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, StorageProvider provider) {
    final item = provider.item;
    final left = item.timeLeft;
    final double ratio = provider.quotaBytes <= 0
        ? 0.0
        : (provider.usedBytes / provider.quotaBytes).clamp(0.0, 1.0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: TmpsColors.surface2,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: TmpsColors.border),
                  ),
                  child: Text(
                    item.code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${item.planName} · ${fmtSize(item.quotaBytes)}',
                    style: const TextStyle(color: TmpsColors.muted, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(
                color: TmpsColors.bg2,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: TmpsColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.url.replaceFirst(RegExp(r'^https?://'), ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.copy, size: 19),
                    tooltip: 'Копировать',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: item.url));
                      if (context.mounted) _toast(context, 'Ссылка скопирована');
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.share, size: 19),
                    tooltip: 'Поделиться',
                    onPressed: () => SharePlus.instance.share(ShareParams(text: item.url)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.external, size: 19),
                    tooltip: 'Открыть в браузере',
                    onPressed: () =>
                        launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Осталось',
                    value: left == null ? 'бессрочно' : fmtLeft(left),
                    sub: item.unlimited ? null : 'до ${fmtDate(item.expiresAt)}',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Занято',
                    value: fmtSize(provider.usedBytes),
                    sub: 'из ${fmtSize(provider.quotaBytes)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ratio.toDouble(),
                minHeight: 6,
                backgroundColor: TmpsColors.surface2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  ratio > 0.95
                      ? TmpsColors.danger
                      : ratio > 0.8
                          ? TmpsColors.warn
                          : TmpsColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filesHeader(StorageProvider provider) {
    final count = provider.files.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Файлы', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text('$count ${plural(count, 'файл', 'файла', 'файлов')}',
            style: const TextStyle(color: TmpsColors.muted, fontSize: 13)),
      ],
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

  Future<void> _confirmDeleteFile(
      BuildContext context, StorageProvider provider, String name) async {
    final ok = await _confirm(context,
        title: 'Удалить «$name»?', text: 'Файл исчезнет у всех, у кого есть ссылка.');
    if (!ok || !context.mounted) return;
    await _run(context, () => provider.deleteFiles([name]), 'Файл удалён');
  }

  Future<void> _onMenu(BuildContext context, StorageProvider provider, String action) async {
    final item = provider.item;
    switch (action) {
      case 'zip':
        unawaited(provider.downloadArchive());
        break;

      case 'rename':
        final title = await _prompt(context, 'Название хранилища', item.title ?? '');
        if (title == null || !context.mounted) return;
        await _run(context, () async {
          final updated = await storages.rename(item.code, title);
          provider.applyItem(updated);
        }, 'Название изменено');
        break;

      case 'extend':
        final hours = await _pickOption<int>(
          context,
          'Продлить хранилище',
          item.extendOptions,
          (h) => '+ ${fmtHours(h)}',
        );
        if (hours == null || !context.mounted) return;
        await _run(context, () async {
          final updated = await storages.extend(item.code, hours);
          provider.applyItem(updated);
        }, 'Срок продлён');
        break;

      case 'plan':
        final option = await _pickPlan(context, item.planOptions);
        if (option == null || !context.mounted) return;
        await _run(context, () async {
          final updated = await storages.changePlan(item.code, option.plan);
          provider.applyItem(updated);
          await provider.load(silent: true);
        }, 'Тариф изменён');
        break;

      case 'access':
        final mode = await _pickOption<String>(
          context,
          'Кто может пользоваться',
          const ['public', 'readonly', 'private'],
          (m) => switch (m) {
            'public' => 'Все, у кого есть ссылка',
            'readonly' => 'Только просмотр и скачивание',
            _ => 'Только я',
          },
          current: item.access,
        );
        if (mode == null || !context.mounted) return;
        await _run(context, () async {
          final updated = await storages.setAccess(item.code, mode);
          provider.applyItem(updated);
        }, 'Режим доступа изменён');
        break;

      case 'rotate':
        final ok = await _confirm(context,
            title: 'Сменить ссылку?',
            text: 'Старая ссылка перестанет работать. Файлы останутся на месте.');
        if (!ok || !context.mounted) return;
        await _run(context, () async {
          final updated = await storages.rotate(item.code);
          provider.applyItem(updated);
        }, 'Ссылка изменена');
        break;

      case 'delete':
        final ok = await _confirm(context,
            title: 'Удалить хранилище?',
            text: 'Файлы удалятся сразу и навсегда. Отменить не получится.',
            danger: true);
        if (!ok || !context.mounted) return;
        try {
          await storages.remove(item.code);
          if (context.mounted) Navigator.of(context).pop();
        } on ApiException catch (e) {
          if (context.mounted) _toast(context, e.message);
        }
        break;
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: TmpsColors.muted, fontSize: 12)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!, style: const TextStyle(color: TmpsColors.faint, fontSize: 12)),
        ],
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context,
    {required String title, required String text, bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text, style: const TextStyle(color: TmpsColors.muted, height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: TmpsColors.danger) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(danger ? 'Удалить' : 'Продолжить'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> _prompt(BuildContext context, String title, String initial) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, maxLength: 64, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<T?> _pickOption<T>(
  BuildContext context,
  String title,
  List<T> options,
  String Function(T) label, {
  T? current,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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

Future<PlanOption?> _pickPlan(BuildContext context, List<PlanOption> options) {
  return showModalBottomSheet<PlanOption>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const Text('Сменить тариф',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Больше объём - меньше срок, меньше объём - больше срок.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TmpsColors.muted, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 10),
          for (final option in options)
            ListTile(
              enabled: option.available,
              leading: TmpsIcon(
                option.isUpgrade ? Ico.arrowUp : Ico.arrowDown,
                color: option.available ? TmpsColors.accent : TmpsColors.faint,
              ),
              title: Text('${option.planName} · ${fmtSize(option.quotaBytes)}'),
              subtitle: Text(
                option.available
                    ? (option.keepsTtl
                        ? 'Срок не меняется'
                        : option.extendable
                            ? 'Продление до ${fmtHours(option.maxLifetimeHours ?? 0)} с момента создания'
                            : 'Без продления')
                    : (option.reason ?? 'Недоступно'),
                style: TextStyle(
                  color: option.available ? TmpsColors.muted : TmpsColors.warn,
                  fontSize: 12.5,
                ),
              ),
              onTap: option.available ? () => Navigator.of(ctx).pop(option) : null,
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
