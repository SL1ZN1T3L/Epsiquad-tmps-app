import 'package:flutter/material.dart';

import '../format.dart';
import '../icons.dart';
import '../models/storage.dart';
import '../theme.dart';

class StorageCard extends StatelessWidget {
  const StorageCard({super.key, required this.item, required this.onTap});

  final StorageItem item;
  final VoidCallback onTap;

  Color get _timerColor {
    final left = item.timeLeft;
    if (left == null) return TmpsColors.muted;
    if (left.inHours < 1) return TmpsColors.danger;
    if (left.inHours < 6) return TmpsColors.warn;
    return TmpsColors.text;
  }

  @override
  Widget build(BuildContext context) {
    final left = item.timeLeft;
    final ratio = item.usedRatio;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        left == null ? 'бессрочно' : fmtLeft(left),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _timerColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.unlimited ? 'без срока' : 'до ${fmtDate(item.expiresAt)}',
                        style: const TextStyle(fontSize: 11.5, color: TmpsColors.faint),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Chip(text: item.code, mono: true),
                  _Chip(text: '${item.planName} · ${fmtSize(item.quotaBytes)}'),
                  if (item.access == 'private')
                    const _Chip(text: 'только я', icon: Ico.lock, color: TmpsColors.warn),
                  if (item.access == 'readonly')
                    const _Chip(text: 'просмотр', icon: Ico.eye),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Занято ${fmtSize(item.usedBytes)}',
                      style: const TextStyle(fontSize: 12.5, color: TmpsColors.muted)),
                  Text('свободно ${fmtSize(item.freeBytes)}',
                      style: const TextStyle(fontSize: 12.5, color: TmpsColors.muted)),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: TmpsColors.surface2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ratio > 0.95
                        ? TmpsColors.danger
                        : ratio > 0.8
                            ? TmpsColors.warn
                            : TmpsColors.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.icon, this.mono = false, this.color});

  final String text;
  final String? icon;
  final bool mono;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: TmpsColors.surface2,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: TmpsColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            TmpsIcon(icon!, size: 13, color: color ?? TmpsColors.muted),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: mono ? FontWeight.w700 : FontWeight.w500,
              fontFamily: mono ? 'monospace' : null,
              color: color ?? TmpsColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
