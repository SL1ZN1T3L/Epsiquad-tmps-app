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

  @override
  Widget build(BuildContext context) {
    final color = _kindColors[file.kind] ?? TmpsColors.muted;
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0x247C6CFF) : TmpsColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? TmpsColors.accent : TmpsColors.border),
        ),
        child: InkWell(
          onTap: selecting ? onToggle : onOpen,
          onLongPress: selecting ? onToggle : onLongPress,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected ? TmpsColors.accent : TmpsColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selected ? TmpsColors.accent : TmpsColors.border),
                  ),
                  child: selected
                      ? const TmpsIcon(Ico.check, size: 20, color: Colors.white)
                      : TmpsIcon(_kindIcons[file.kind] ?? Ico.file, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${fmtSize(file.shownSize)} · ${fmtRelative(file.modifiedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: TmpsColors.muted, fontSize: 12),
                            ),
                          ),
                          if (showStats) ...[
                            const SizedBox(width: 10),
                            const TmpsIcon(Ico.eye, size: 13, color: TmpsColors.faint),
                            const SizedBox(width: 3),
                            Text('${stats?.views ?? 0}',
                                style: const TextStyle(color: TmpsColors.faint, fontSize: 12)),
                            const SizedBox(width: 8),
                            const TmpsIcon(Ico.download, size: 13, color: TmpsColors.faint),
                            const SizedBox(width: 3),
                            Text('${stats?.downloads ?? 0}',
                                style: const TextStyle(color: TmpsColors.faint, fontSize: 12)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (!selecting)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.download, size: 19),
                    tooltip: 'Скачать',
                    onPressed: onDownload,
                  ),
                if (!selecting && onShare != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.share, size: 19),
                    tooltip: 'Поделиться ссылкой',
                    onPressed: onShare,
                  ),
                if (canDelete && !selecting)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const TmpsIcon(Ico.trash, size: 19, color: TmpsColors.danger),
                    tooltip: 'Удалить',
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
