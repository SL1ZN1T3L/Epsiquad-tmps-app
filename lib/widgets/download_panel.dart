import 'package:flutter/material.dart';

import '../icons.dart';
import '../providers/storage_provider.dart';
import '../theme.dart';
import 'dialog_actions.dart';

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
          DialogActions(children: [
            FilledButton(
              style: DialogActions.primaryStyle(ctx),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отменить всё'),
            ),
            TextButton(
              style: DialogActions.dangerStyle(ctx),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Нет'),
            ),
          ]),
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
    final pausable = jobs.any((d) => d.running && d.pauseEnabled);

    final title = running > 0
        ? 'Скачивание'
        : (canceled == jobs.length
            ? 'Скачивание отменено'
            : 'Скачивание завершено');

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
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
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
              // Обе кнопки видны всегда, пока идёт скачивание. Если паузу
              // нельзя применить (архив или сервер без докачки), кнопка
              // неактивна, а причина написана в строке файла ниже.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: TmpsIcon(paused ? Ico.play : Ico.pause, size: 18),
                      label: Text(paused ? 'Продолжить' : 'Пауза'),
                      onPressed: paused
                          ? provider.resumeAllDownloads
                          : (pausable ? provider.pauseAllDownloads : null),
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
    final percent = '${(job.progress * 100).round()} %';
    if (job.paused) return 'на паузе · $percent';
    if (!job.canPause) return '$percent · архив нельзя ставить на паузу';
    if (job.pauseSupported == false) {
      return '$percent · сервер не поддерживает паузу для этого файла';
    }
    return percent;
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
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _info,
                        style: TextStyle(
                          fontSize: 12,
                          color: job.error != null
                              ? TmpsColors.danger
                              : TmpsColors.muted,
                        ),
                      ),
                      if (job.hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            job.hint!,
                            style: const TextStyle(
                                fontSize: 12, color: TmpsColors.danger),
                          ),
                        ),
                    ],
                  ),
                ),
                if (job.running)
                  IconButton(
                    icon: TmpsIcon(job.paused ? Ico.play : Ico.pause, size: 22),
                    tooltip: job.paused ? 'Продолжить' : 'Пауза',
                    onPressed: job.paused
                        ? () => provider.resumeDownload(job)
                        : (job.pauseEnabled
                            ? () => provider.pauseDownload(job)
                            : null),
                  ),
                if (job.running)
                  IconButton(
                    icon: const TmpsIcon(Ico.x, size: 22),
                    tooltip: 'Отменить',
                    onPressed: () => provider.cancelDownload(job),
                  )
                else ...[
                  if (job.done)
                    IconButton(
                      icon: const TmpsIcon(Ico.external, size: 21),
                      tooltip: 'Открыть',
                      onPressed: () => provider.openDownload(job),
                    ),
                  if (job.canRetry)
                    IconButton(
                      icon: const TmpsIcon(Ico.refresh, size: 21),
                      tooltip: 'Повторить',
                      onPressed: () => provider.retryDownload(job),
                    ),
                  IconButton(
                    icon: const TmpsIcon(Ico.x, size: 22),
                    tooltip: 'Убрать из списка',
                    onPressed: () => provider.forgetDownload(job),
                  ),
                ],
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
