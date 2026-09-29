import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../icons.dart';
import '../providers/app_provider.dart';
import '../services/update_service.dart';
import '../theme.dart';

enum _Stage { ready, downloading, checking, done, failed, missing }

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.app, required this.release});

  final AppProvider app;
  final ReleaseInfo release;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _Stage _stage = _Stage.ready;
  double _progress = 0;
  String? _error;
  File? _file;
  ReleaseAsset? _apk;

  @override
  void initState() {
    super.initState();
    _apk = widget.release.apkFor(widget.app.abis);
    if (_apk == null) _stage = _Stage.missing;
  }

  Future<void> _run() async {
    final apk = _apk;
    if (apk == null) return;
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _error = null;
    });
    try {
      final file = await widget.app.updates.download(
        apk,
        checksum: widget.release.checksumFor(apk),
        onProgress: (value) {
          if (!mounted) return;
          setState(() {
            _progress = value;
            if (value >= 1 && _stage == _Stage.downloading) _stage = _Stage.checking;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _file = file;
        _stage = _Stage.done;
      });
      await widget.app.updates.install(file);
    } on UpdateFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = 'Не удалось обновиться';
      });
    }
  }

  Future<void> _openInstaller() async {
    final file = _file;
    if (file == null) return;
    try {
      await widget.app.updates.install(file);
    } on UpdateFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = e.message;
      });
    }
  }

  String get _status {
    switch (_stage) {
      case _Stage.ready:
        final size = _apk?.size ?? 0;
        return size > 0 ? '${_apk!.name} · ${fmtSize(size)}' : (_apk?.name ?? '');
      case _Stage.downloading:
        return 'Скачивание, ${(_progress * 100).round()} %';
      case _Stage.checking:
        return 'Проверка контрольной суммы';
      case _Stage.done:
        return 'Файл проверен, открывается установщик';
      case _Stage.failed:
        return _error ?? 'Не удалось обновиться';
      case _Stage.missing:
        return 'В релизе нет файла под ваше устройство';
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _stage == _Stage.downloading || _stage == _Stage.checking;
    return AlertDialog(
      backgroundColor: TmpsColors.bg2,
      title: Text('Версия ${widget.release.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _status,
            style: TextStyle(
              color: _stage == _Stage.failed ? TmpsColors.danger : TmpsColors.muted,
              fontSize: 13,
            ),
          ),
          if (busy || _stage == _Stage.done) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _stage == _Stage.checking ? null : _progress,
                minHeight: 4,
                backgroundColor: TmpsColors.border,
                valueColor: const AlwaysStoppedAnimation<Color>(TmpsColors.accent),
              ),
            ),
          ],
          if (_stage == _Stage.ready || _stage == _Stage.failed) ...[
            const SizedBox(height: 14),
            const Text(
              'Файл скачивается с GitHub и сверяется с опубликованной контрольной суммой. Установку подтверждает система.',
              style: TextStyle(color: TmpsColors.faint, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(widget.release.pageUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Страница релиза'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
        if (_stage == _Stage.ready || _stage == _Stage.failed)
          FilledButton.icon(
            onPressed: _apk == null ? null : _run,
            icon: const TmpsIcon(Ico.download, size: 18),
            label: Text(_stage == _Stage.failed ? 'Повторить' : 'Обновить'),
          ),
        if (_stage == _Stage.done)
          FilledButton.icon(
            onPressed: _openInstaller,
            icon: const TmpsIcon(Ico.check, size: 18),
            label: const Text('Установить'),
          ),
      ],
    );
  }
}
