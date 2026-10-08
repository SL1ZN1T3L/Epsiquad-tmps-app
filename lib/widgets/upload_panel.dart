import 'package:flutter/material.dart';

import '../format.dart';
import '../icons.dart';
import '../providers/storage_provider.dart';
import '../theme.dart';

class UploadPanel extends StatelessWidget {
  const UploadPanel({super.key, required this.provider});

  final StorageProvider provider;

  Future<void> _confirmCancelAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить все загрузки?'),
        content: const Text('Файлы, которые ещё не загрузились, не сохранятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить всё', style: TextStyle(color: TmpsColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) provider.cancelAll();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = provider.uploads;
    if (tasks.isEmpty) return const SizedBox.shrink();

    final active = tasks.where((t) => t.active).length;
    final done = tasks.where((t) => t.status == UploadStatus.done).length;
    final canceled = tasks.where((t) => t.status == UploadStatus.canceled).length;
    final paused = tasks.any((t) => t.status == UploadStatus.paused);
    final totalBytes = tasks.where((t) => t.status != UploadStatus.canceled).fold<int>(0, (a, t) => a + t.size);
    final sentBytes = tasks.where((t) => t.status != UploadStatus.canceled).fold<int>(
          0,
          (a, t) => a + (t.status == UploadStatus.done ? t.size : t.sentBytes),
        );

    final title = active > 0
        ? 'Загрузка · $done из ${tasks.length}'
        : (canceled == tasks.length ? 'Загрузка отменена' : 'Загрузка завершена');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        totalBytes > 0
                            ? '${fmtSize(sentBytes)} из ${fmtSize(totalBytes)}'
                            : '${tasks.length} ${plural(tasks.length, 'файл', 'файла', 'файлов')}',
                        style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (active == 0)
                  TextButton(
                    onPressed: provider.clearFinished,
                    child: const Text('Скрыть'),
                  ),
              ],
            ),
            if (active > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: TmpsIcon(paused ? Ico.play : Ico.pause, size: 18),
                      label: Text(paused ? 'Продолжить' : 'Пауза'),
                      onPressed: paused ? provider.resumeAll : provider.pauseAll,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TmpsColors.danger,
                        side: const BorderSide(color: Color(0x4DFB4B6B)),
                      ),
                      icon: const TmpsIcon(Ico.x, size: 18),
                      label: const Text('Отменить всё'),
                      onPressed: () => _confirmCancelAll(context),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            for (final task in tasks) _UploadRow(provider: provider, task: task),
          ],
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow({required this.provider, required this.task});

  final StorageProvider provider;
  final UploadTask task;

  String get _info {
    switch (task.status) {
      case UploadStatus.queued:
        return 'в очереди · ${fmtSize(task.size)}';
      case UploadStatus.uploading:
        return '${fmtSize(task.sentBytes)} из ${fmtSize(task.size)} · ${(task.progress * 100).round()}%';
      case UploadStatus.paused:
        return 'на паузе · ${fmtSize(task.sentBytes)} из ${fmtSize(task.size)}';
      case UploadStatus.done:
        return '${fmtSize(task.size)} · загружено';
      case UploadStatus.canceled:
        return 'отменено';
      case UploadStatus.error:
        return task.error ?? 'ошибка';
    }
  }

  Color get _barColor {
    switch (task.status) {
      case UploadStatus.done:
        return TmpsColors.ok;
      case UploadStatus.error:
        return TmpsColors.danger;
      case UploadStatus.paused:
        return TmpsColors.faint;
      default:
        return TmpsColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TmpsColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TmpsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _info,
                        style: TextStyle(
                          fontSize: 12,
                          color: task.status == UploadStatus.error ? TmpsColors.danger : TmpsColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (task.status == UploadStatus.uploading || task.status == UploadStatus.queued)
                  IconButton(
                    icon: const TmpsIcon(Ico.pause, size: 22),
                    tooltip: 'Пауза',
                    onPressed: () => provider.pause(task),
                  ),
                if (task.status == UploadStatus.paused || task.status == UploadStatus.error)
                  IconButton(
                    icon: const TmpsIcon(Ico.play, size: 22),
                    tooltip: 'Продолжить',
                    onPressed: () => provider.resume(task),
                  ),
                if (task.active || task.status == UploadStatus.error)
                  IconButton(
                    icon: const TmpsIcon(Ico.x, size: 22),
                    tooltip: task.active ? 'Отменить' : 'Убрать',
                    onPressed: () => provider.cancel(task),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: task.status == UploadStatus.done ? 1 : task.progress,
                minHeight: 4,
                backgroundColor: TmpsColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(_barColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
