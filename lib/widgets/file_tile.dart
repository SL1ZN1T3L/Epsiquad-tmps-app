import 'package:flutter/material.dart';

import '../format.dart';
import '../icons.dart';
import '../models/storage_file.dart';
import '../theme.dart';

const _kindIcons = <String, String>{
  'image': Ico.image,
  'video': Ico.video,
  'audio': Ico.audio,
  'pdf': Ico.pdf,
  'text': Ico.file,
  'code': Ico.code,
  'archive': Ico.zip,
};

const _kindColors = <String, Color>{
  'image': Color(0xFFA78BFA),
  'video': Color(0xFFF472B6),
  'audio': Color(0xFFFBBF24),
  'pdf': Color(0xFFFB7185),
  'text': Color(0xFF93A3B8),
  'code': Color(0xFF34D399),
  'archive': Color(0xFF60A5FA),
};

class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.file,
    required this.stats,
    required this.showStats,
    required this.onOpen,
    required this.onLongPress,
    required this.onToggle,
    required this.selecting,
    required this.selected,
    required this.onShare,
    required this.onDownload,
    required this.onDelete,
    required this.canDelete,
    this.thumbnailUri,
    this.thumbnailHeaders,
  });

  final StorageFile file;
  final FileStats? stats;
  final bool showStats;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final VoidCallback onToggle;

  /// Идёт выбор нескольких файлов: нажатие отмечает файл, кнопки скрыты.
  final bool selecting;
  final bool selected;

  /// null - ссылку на файл дать нельзя (в зашифрованном хранилище по ней отдаётся шифртекст).
  final VoidCallback? onShare;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final bool canDelete;

  /// Для обычных изображений показываем миниатюру; E2EE сюда не передаётся.
  final Uri? thumbnailUri;
  final Map<String, String>? thumbnailHeaders;

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  file.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (onShare != null)
              ListTile(
                leading: const TmpsIcon(Ico.share, color: TmpsColors.accent),
                title: const Text('Поделиться ссылкой'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onShare!();
                },
              ),
            if (canDelete)
              ListTile(
                leading: const TmpsIcon(Ico.trash, color: TmpsColors.danger),
                title: const Text('Удалить', style: TextStyle(color: TmpsColors.danger)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onDelete();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _leading() {
    final color = _kindColors[file.kind] ?? TmpsColors.muted;
    final icon = TmpsIcon(
      _kindIcons[file.kind] ?? Ico.file,
      size: 20,
      color: selected ? Colors.white : color,
    );
    final uri = thumbnailUri;
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected ? TmpsColors.accent : TmpsColors.surface2,
        borderRadius: BorderRadius.circular(11),
      ),
      child: selected
          ? const TmpsIcon(Ico.check, size: 21, color: Colors.white)
          : uri == null
              ? icon
              : Image.network(
                  uri.toString(),
                  headers: thumbnailHeaders,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : icon,
                  errorBuilder: (context, error, stackTrace) => icon,
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMenu = onShare != null || canDelete;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0x247C6CFF) : TmpsColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? TmpsColors.accent : TmpsColors.border),
        ),
        child: InkWell(
          onTap: selecting ? onToggle : onOpen,
          onLongPress: selecting ? onToggle : onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                _leading(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 3,
                        children: [
                          Text(
                            '${fmtSize(file.shownSize)} · ${fmtRelative(file.modifiedAt)}',
                            style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                          ),
                          if (showStats)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const TmpsIcon(Ico.eye, size: 13, color: TmpsColors.muted),
                                const SizedBox(width: 4),
                                Text(
                                  '${stats?.views ?? 0}',
                                  style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                                ),
                                const SizedBox(width: 9),
                                const TmpsIcon(Ico.download, size: 13, color: TmpsColors.muted),
                                const SizedBox(width: 4),
                                Text(
                                  '${stats?.downloads ?? 0}',
                                  style: const TextStyle(color: TmpsColors.muted, fontSize: 12.5),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!selecting)
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: const TmpsIcon(Ico.download, size: 20),
                    tooltip: 'Скачать',
                    onPressed: onDownload,
                  ),
                if (!selecting && hasMenu)
                  IconButton(
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: const TmpsIcon(Ico.more, size: 20),
                    tooltip: 'Действия с файлом',
                    onPressed: () => _showActions(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FileTileSkeleton extends StatelessWidget {
  const FileTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 76,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TmpsColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            _SkeletonBox(width: 44, height: 44, radius: 11),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SkeletonBox(width: 210, height: 13, radius: 6),
                  SizedBox(height: 9),
                  _SkeletonBox(width: 135, height: 10, radius: 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height, required this.radius});

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: TmpsColors.surface2,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
