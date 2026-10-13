import 'package:flutter/material.dart';

import '../icons.dart';
import '../theme.dart';
import 'dialog_actions.dart';

class DevModeMenu extends StatelessWidget {
  const DevModeMenu({super.key});

  Future<void> _showUpdatePreview(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обновление доступно'),
        content: const Text(
          'Демо-окно. Сеть отключена, скачивание и установка не выполняются.',
          style: TextStyle(color: TmpsColors.muted, height: 1.4),
        ),
        actions: [
          DialogActions(children: [
            FilledButton(
              style: DialogActions.primaryStyle(context),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Dev Mode: скачивание отключено')),
                );
              },
              child: const Text('Скачать'),
            ),
            TextButton(
              style: DialogActions.dangerStyle(context),
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _showConfirmation(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отменить загрузки?'),
        content: const Text(
          'Демо-окно подтверждения. Никакие файлы не изменяются.',
          style: TextStyle(color: TmpsColors.muted, height: 1.4),
        ),
        actions: [
          DialogActions(children: [
            FilledButton(
              style: DialogActions.primaryStyle(context),
              onPressed: () => Navigator.pop(context),
              child: const Text('Отменить'),
            ),
            TextButton(
              style: DialogActions.dangerStyle(context),
              onPressed: () => Navigator.pop(context),
              child: const Text('Нет'),
            ),
          ]),
        ],
      ),
    );
  }

  void _showProgress(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Скачивание'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: 0.62),
            SizedBox(height: 14),
            Text('Демо-прогресс · 62 %',
                style: TextStyle(color: TmpsColors.muted)),
          ],
        ),
        actions: [
          DialogActions(children: [
            TextButton(
              style: DialogActions.dangerStyle(context),
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ]),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Демо-уведомление: операция завершена')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageContext = context;
    return FloatingActionButton(
      heroTag: 'dev-mode',
      backgroundColor: TmpsColors.warn,
      foregroundColor: TmpsColors.bg,
      tooltip: 'Dev Mode',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('DEV MODE · OFFLINE',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: TmpsColors.warn)),
                const SizedBox(height: 14),
                ListTile(
                  leading:
                      const TmpsIcon(Ico.download, color: TmpsColors.accent),
                  title: const Text('Окно обновления'),
                  onTap: () {
                    Navigator.pop(context);
                    _showUpdatePreview(pageContext);
                  },
                ),
                ListTile(
                  leading: const TmpsIcon(Ico.warning, color: TmpsColors.warn),
                  title: const Text('Окно подтверждения'),
                  onTap: () {
                    Navigator.pop(context);
                    _showConfirmation(pageContext);
                  },
                ),
                ListTile(
                  leading:
                      const TmpsIcon(Ico.download, color: TmpsColors.accent2),
                  title: const Text('Состояние загрузки'),
                  onTap: () {
                    Navigator.pop(context);
                    _showProgress(pageContext);
                  },
                ),
                ListTile(
                  leading: const TmpsIcon(Ico.alert, color: TmpsColors.muted),
                  title: const Text('Показать уведомление'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar(pageContext);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      child: const TmpsIcon(Ico.code, size: 22),
    );
  }
}
