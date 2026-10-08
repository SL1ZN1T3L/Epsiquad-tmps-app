import 'package:flutter/material.dart';

import '../icons.dart';
import '../providers/storage_provider.dart';
import '../theme.dart';

class DownloadPanel extends StatelessWidget {
  const DownloadPanel({super.key, required this.provider});

  final StorageProvider provider;

  Future<void> _confirmCancelAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить все скачивания?'),
        content: const Text('Недокачанные файлы не сохранятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить всё', style: TextStyle(color: TmpsColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) provider.cancelAllDownloads();
  }

  @override
  Widget build(BuildContext context) {
    final jobs = provider.downloads;
    if (jobs.isEmpty) return const SizedBox.shrink();

    final running = jobs.where((d) => d.running).length;
    final canceled = jobs.where((d) => d.canceled).length;
    final paused = jobs.any((d) => d.running && d.paused);
    final canPause = jobs.any((d) => d.running && d.canPause);

    final title = running > 0
        ? 'Скачивание'
        : (canceled == jobs.length ? 'Скачивание отменено' : 'Скачивание завершено');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (running == 0)
                  TextButton(
                    onPressed: provider.clearFinishedDownloads,
                    child: const Text('Убрать'),
                  ),
              ],
            ),
            if (running > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (canPause || paused) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: TmpsIcon(paused ? Ico.play : Ico.pause, size: 18),
                        label: Text(paused ? 'Продолжить' : 'Пауза'),
                        onPressed: paused ? provider.resumeAllDownloads : provider.pauseAllDownloads,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: TmpsColors.danger,
                        side: const BorderSide(color: Color(0x4DFB4B6B)),
                      ),
                      icon: const TmpsIcon(Ico.x, size: 18),
                      label: Text(running > 1 ? 'Отменить всё' : 'Отменить'),
                      onPressed: () => _confirmCancelAll(context),
                    ),
                  ),
                ],
              ),
            ],
            for (final job in jobs) _DownloadRow(job: job, provider: provider),
          ],
        ),
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.job, required this.provider});

  final FileDownload job;
  final StorageProvider provider;

  String get _info {
    if (job.error != null) return job.error!;
    if (job.canceled) return 'отменено';
    if (job.done) return 'Сохранено в «Загрузки»';
    if (job.paused) return 'на паузе · ${(job.progress * 100).round()} %';
    return '${(job.progress * 100).round()} %';
  }

  Color get _color {
    if (job.error != null) return TmpsColors.danger;
    if (job.done) return TmpsColors.ok;
    if (job.paused || job.canceled) return TmpsColors.faint;
    return TmpsColors.accent;
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
                        job.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _info,
                        style: TextStyle(
                          fontSize: 12,
                          color: job.error != null ? TmpsColors.danger : TmpsColors.muted,
                        ),
                      ),
                      if (job.hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            job.hint!,
                            style: const TextStyle(fontSize: 12, color: TmpsColors.danger),
                          ),
                        ),
                    ],
                  ),
                ),
                if (job.running && job.canPause && !job.paused)
                  IconButton(
                    icon: const TmpsIcon(Ico.pause, size: 22),
                    tooltip: 'Пауза',
                    onPressed: () => provider.pauseDownload(job),
                  ),
                if (job.running && job.paused)
                  IconButton(
                    icon: const TmpsIcon(Ico.play, size: 22),
                    tooltip: 'Продолжить',
                    onPressed: () => provider.resumeDownload(job),
                  ),
                if (job.running)
                  IconButton(
                    icon: const TmpsIcon(Ico.x, size: 22),
                    tooltip: 'Отменить',
                    onPressed: () => provider.cancelDownload(job),
                  )
                else
                  IconButton(
                    icon: const TmpsIcon(Ico.x, size: 22),
                    tooltip: 'Убрать из списка',
                    onPressed: () => provider.forgetDownload(job),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: job.error != null ? 1 : job.progress,
                minHeight: 4,
                backgroundColor: TmpsColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(_color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
