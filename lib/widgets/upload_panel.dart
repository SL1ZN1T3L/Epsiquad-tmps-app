import 'package:flutter/material.dart';

import '../format.dart';
import '../icons.dart';
import '../providers/storage_provider.dart';
import '../theme.dart';

class UploadPanel extends StatelessWidget {
  const UploadPanel({super.key, required this.provider});

  final StorageProvider provider;

  @override
  Widget build(BuildContext context) {
    final tasks = provider.uploads;
    if (tasks.isEmpty) return const SizedBox.shrink();

    final active = tasks.where((t) => t.active).length;
    final done = tasks.where((t) => t.status == UploadStatus.done).length;

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
                        active > 0 ? 'Загрузка' : 'Загрузка завершена',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$done из ${tasks.length} ${plural(tasks.length, 'файл', 'файла', 'файлов')}',
                        style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (active > 0)
                  IconButton(
                    tooltip: provider.uploads.any((t) => t.status == UploadStatus.paused)
                        ? 'Продолжить все'
                        : 'Пауза для всех',
                    icon: TmpsIcon(
                      provider.uploads.any((t) => t.status == UploadStatus.paused)
                          ? Ico.play
                          : Ico.pause,
                    ),
                    onPressed: () {
                      if (provider.uploads.any((t) => t.status == UploadStatus.paused)) {
                        provider.resumeAll();
                      } else {
                        provider.pauseAll();
                      }
                    },
                  )
                else
                  TextButton(
                    onPressed: provider.clearFinished,
                    child: const Text('Скрыть'),
                  ),
              ],
            ),
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
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.pause, size: 20),
                    tooltip: 'Пауза',
                    onPressed: () => provider.pause(task),
                  ),
                if (task.status == UploadStatus.paused || task.status == UploadStatus.error)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.play, size: 20),
                    tooltip: 'Продолжить',
                    onPressed: () => provider.resume(task),
                  ),
                if (task.active)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.x, size: 20),
                    tooltip: 'Отменить',
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
