import 'package:flutter/material.dart';

import '../format.dart';
import '../icons.dart';
import '../providers/storage_provider.dart';
import '../theme.dart';
import 'dialog_actions.dart';

/// Единая сворачиваемая очередь загрузок и скачиваний.
class TransfersPanel extends StatefulWidget {
  const TransfersPanel({super.key, required this.provider});

  final StorageProvider provider;

  @override
  State<TransfersPanel> createState() => _TransfersPanelState();
}

class _TransfersPanelState extends State<TransfersPanel> {
  bool _expanded = true;
  int _previousActive = 0;
  int _previousCount = 0;

  StorageProvider get provider => widget.provider;

  int get _active =>
      provider.uploads.where((task) => task.active).length +
      provider.downloads.where((job) => job.running).length;

  int get _count => provider.uploads.length + provider.downloads.length;

  bool get _hasErrors =>
      provider.uploads.any((task) => task.status == UploadStatus.error) ||
      provider.downloads.any((job) => job.error != null);

  @override
  void initState() {
    super.initState();
    _previousActive = _active;
    _previousCount = _count;
    provider.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant TransfersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != provider) {
      oldWidget.provider.removeListener(_onChanged);
      provider.addListener(_onChanged);
      _previousActive = _active;
      _previousCount = _count;
    }
  }

  @override
  void dispose() {
    provider.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final active = _active;
    final count = _count;
    final shouldCollapse =
        (_previousActive > 0 && active == 0 && !_hasErrors) || count == 0;
    final shouldOpen = _previousCount == 0 && count > 0;
    _previousActive = active;
    _previousCount = count;
    if (!mounted || (!shouldCollapse && !shouldOpen)) return;
    setState(() {
      if (shouldCollapse) _expanded = false;
      if (shouldOpen) _expanded = true;
    });
  }

  double get _progress {
    final values = <double>[
      for (final task in provider.uploads)
        if (task.status != UploadStatus.canceled)
          task.status == UploadStatus.done ? 1 : task.progress,
      for (final job in provider.downloads)
        if (!job.canceled) job.done ? 1 : job.progress,
    ];
    if (values.isEmpty) return 0;
    return values.fold<double>(0, (sum, value) => sum + value) / values.length;
  }

  Color get _color {
    if (_hasErrors) return TmpsColors.danger;
    if (_active == 0 && _count > 0) return TmpsColors.ok;
    return TmpsColors.accent;
  }

  String get _subtitle {
    final uploads = provider.uploads.length;
    final downloads = provider.downloads.length;
    final errors = provider.uploads.where((t) => t.status == UploadStatus.error).length +
        provider.downloads.where((j) => j.error != null).length;
    if (errors > 0) return '$errors ${plural(errors, 'ошибка', 'ошибки', 'ошибок')} · нажмите для подробностей';
    final parts = <String>[
      if (uploads > 0) '$uploads ${plural(uploads, 'загрузка', 'загрузки', 'загрузок')}',
      if (downloads > 0) '$downloads ${plural(downloads, 'скачивание', 'скачивания', 'скачиваний')}',
    ];
    if (_active > 0) return '${parts.join(' · ')} · активных: $_active';
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return Card(
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: TmpsColors.surface2,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: TmpsIcon(Ico.refresh, size: 19, color: _color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _active > 0 ? 'Передачи · активных: $_active' : 'Передачи',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _subtitle,
                              style: TextStyle(color: _hasErrors ? TmpsColors.danger : TmpsColors.muted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const TmpsIcon(Ico.arrowDown, size: 19, color: TmpsColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 4,
                      backgroundColor: TmpsColors.surface2,
                      valueColor: AlwaysStoppedAnimation<Color>(_color),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  const Divider(height: 8),
                  if (provider.uploads.isNotEmpty) _UploadSection(provider: provider),
                  if (provider.downloads.isNotEmpty) _DownloadSection(provider: provider),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirmCancelTransfers(
  BuildContext context, {
  required String title,
  required String text,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(text, style: const TextStyle(color: TmpsColors.muted, height: 1.4)),
      actions: [
        DialogActions(
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: TmpsColors.danger,
                side: const BorderSide(color: TmpsColors.danger),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Отменить передачи'),
            ),
            TextButton(
              style: DialogActions.cancelStyle(dialogContext),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Назад'),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}

class _UploadSection extends StatelessWidget {
  const _UploadSection({required this.provider});

  final StorageProvider provider;

  @override
  Widget build(BuildContext context) {
    final tasks = provider.uploads;
    final active = tasks.any((task) => task.active);
    final paused = tasks.any((task) => task.status == UploadStatus.paused);
    return Column(
      children: [
        _SectionHeader(
          icon: Ico.upload,
          title: 'Загрузки · ${tasks.length}',
          primaryIcon: active ? (paused ? Ico.play : Ico.pause) : null,
          primaryTooltip: paused ? 'Продолжить все' : 'Приостановить все',
          onPrimary: paused ? provider.resumeAll : provider.pauseAll,
          secondaryIcon: active ? Ico.x : Ico.trash,
          secondaryTooltip: active ? 'Отменить все' : 'Очистить список',
          onSecondary: () async {
            if (!active) {
              provider.clearFinished();
              return;
            }
            if (await _confirmCancelTransfers(
              context,
              title: 'Отменить все загрузки?',
              text: 'Файлы, которые ещё не загрузились, не сохранятся.',
            )) {
              await provider.cancelAll();
            }
          },
        ),
        for (final task in tasks) _UploadRow(provider: provider, task: task),
      ],
    );
  }
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({required this.provider});

  final StorageProvider provider;

  @override
  Widget build(BuildContext context) {
    final jobs = provider.downloads;
    final running = jobs.any((job) => job.running);
    final paused = jobs.any((job) => job.running && job.paused);
    final pausable = jobs.any((job) => job.running && job.pauseEnabled);
    return Column(
      children: [
        _SectionHeader(
          icon: Ico.download,
          title: 'Скачивания · ${jobs.length}',
          primaryIcon: running ? (paused ? Ico.play : Ico.pause) : null,
          primaryTooltip: paused ? 'Продолжить все' : 'Приостановить все',
          onPrimary: paused
              ? provider.resumeAllDownloads
              : (pausable ? provider.pauseAllDownloads : null),
          secondaryIcon: running ? Ico.x : Ico.trash,
          secondaryTooltip: running ? 'Отменить все' : 'Очистить список',
          onSecondary: () async {
            if (!running) {
              provider.clearFinishedDownloads();
              return;
            }
            if (await _confirmCancelTransfers(
              context,
              title: 'Отменить все скачивания?',
              text: 'Недокачанные файлы не сохранятся.',
            )) {
              await provider.cancelAllDownloads();
            }
          },
        ),
        for (final job in jobs) _DownloadRow(provider: provider, job: job),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.secondaryIcon,
    required this.secondaryTooltip,
    required this.onSecondary,
    this.primaryIcon,
    this.primaryTooltip,
    this.onPrimary,
  });

  final String icon;
  final String title;
  final String? primaryIcon;
  final String? primaryTooltip;
  final VoidCallback? onPrimary;
  final String secondaryIcon;
  final String secondaryTooltip;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TmpsIcon(icon, size: 18, color: TmpsColors.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
        if (primaryIcon != null)
          IconButton(
            icon: TmpsIcon(primaryIcon!, size: 19),
            tooltip: primaryTooltip,
            onPressed: onPrimary == null ? null : () => onPrimary!(),
          ),
        IconButton(
          icon: TmpsIcon(secondaryIcon, size: 19),
          tooltip: secondaryTooltip,
          onPressed: () => onSecondary(),
        ),
      ],
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.name,
    required this.info,
    required this.progress,
    required this.color,
    required this.actions,
    this.hint,
  });

  final String name;
  final String info;
  final double progress;
  final Color color;
  final List<Widget> actions;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TmpsColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    const SizedBox(height: 3),
                    Text(info, style: TextStyle(fontSize: 12.5, color: color == TmpsColors.danger ? color : TmpsColors.muted)),
                    if (hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(hint!, style: const TextStyle(fontSize: 12.5, color: TmpsColors.danger)),
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: TmpsColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
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
        return 'В очереди · ${fmtSize(task.size)}';
      case UploadStatus.uploading:
        return '${fmtSize(task.sentBytes)} из ${fmtSize(task.size)} · ${(task.progress * 100).round()}%';
      case UploadStatus.paused:
        return 'На паузе · ${fmtSize(task.sentBytes)} из ${fmtSize(task.size)}';
      case UploadStatus.done:
        return '${fmtSize(task.size)} · загружено';
      case UploadStatus.canceled:
        return 'Отменено';
      case UploadStatus.error:
        return task.error ?? 'Ошибка загрузки';
    }
  }

  Color get _color {
    switch (task.status) {
      case UploadStatus.done:
        return TmpsColors.ok;
      case UploadStatus.error:
        return TmpsColors.danger;
      case UploadStatus.paused:
      case UploadStatus.canceled:
        return TmpsColors.faint;
      default:
        return TmpsColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _TransferRow(
      name: task.name,
      info: _info,
      progress: task.status == UploadStatus.done || task.status == UploadStatus.error ? 1 : task.progress,
      color: _color,
      actions: [
        if (task.status == UploadStatus.uploading || task.status == UploadStatus.queued)
          IconButton(icon: const TmpsIcon(Ico.pause, size: 20), tooltip: 'Пауза', onPressed: () => provider.pause(task)),
        if (task.status == UploadStatus.paused)
          IconButton(icon: const TmpsIcon(Ico.play, size: 20), tooltip: 'Продолжить', onPressed: () => provider.resume(task)),
        if (task.status == UploadStatus.error)
          IconButton(icon: const TmpsIcon(Ico.refresh, size: 20), tooltip: 'Повторить', onPressed: () => provider.resume(task)),
        if (task.active || task.status == UploadStatus.error)
          IconButton(
            icon: const TmpsIcon(Ico.x, size: 20),
            tooltip: task.active ? 'Отменить' : 'Убрать',
            onPressed: () => provider.cancel(task),
          ),
      ],
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.provider, required this.job});

  final StorageProvider provider;
  final FileDownload job;

  String get _info {
    if (job.error != null) return job.error!;
    if (job.canceled) return 'Отменено';
    if (job.done) return 'Сохранено в «Загрузки»';
    final percent = '${(job.progress * 100).round()} %';
    if (job.paused) return 'На паузе · $percent';
    if (!job.canPause) return '$percent · архив нельзя ставить на паузу';
    if (job.pauseSupported == false) return '$percent · пауза не поддерживается сервером';
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
    return _TransferRow(
      name: job.name,
      info: _info,
      hint: job.hint,
      progress: job.error != null ? 1 : job.progress,
      color: _color,
      actions: [
        if (job.running)
          IconButton(
            icon: TmpsIcon(job.paused ? Ico.play : Ico.pause, size: 20),
            tooltip: job.paused ? 'Продолжить' : 'Пауза',
            onPressed: job.paused
                ? () => provider.resumeDownload(job)
                : (job.pauseEnabled ? () => provider.pauseDownload(job) : null),
          ),
        if (job.running)
          IconButton(icon: const TmpsIcon(Ico.x, size: 20), tooltip: 'Отменить', onPressed: () => provider.cancelDownload(job)),
        if (!job.running && job.done)
          IconButton(icon: const TmpsIcon(Ico.external, size: 20), tooltip: 'Открыть', onPressed: () => provider.openDownload(job)),
        if (!job.running && job.canRetry)
          IconButton(icon: const TmpsIcon(Ico.refresh, size: 20), tooltip: 'Повторить', onPressed: () => provider.retryDownload(job)),
        if (!job.running)
          IconButton(icon: const TmpsIcon(Ico.x, size: 20), tooltip: 'Убрать из списка', onPressed: () => provider.forgetDownload(job)),
      ],
    );
  }
}
