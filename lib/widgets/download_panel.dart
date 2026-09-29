import 'package:flutter/material.dart';

import '../icons.dart';
import '../providers/storage_provider.dart';
import '../theme.dart';

class DownloadPanel extends StatelessWidget {
  const DownloadPanel({super.key, required this.provider});

  final StorageProvider provider;

  @override
  Widget build(BuildContext context) {
    final jobs = provider.downloads;
    if (jobs.isEmpty) return const SizedBox.shrink();

    final running = jobs.where((d) => d.running).length;

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
                    running > 0 ? 'Скачивание' : 'Скачивание завершено',
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
    if (job.done) return 'Сохранено в «Загрузки»';
    return '${(job.progress * 100).round()} %';
  }

  Color get _color {
    if (job.error != null) return TmpsColors.danger;
    if (job.done) return TmpsColors.ok;
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
                    ],
                  ),
                ),
                if (!job.running)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.x, size: 20),
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
