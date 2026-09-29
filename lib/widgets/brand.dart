import 'package:flutter/material.dart';

import '../icons.dart';
import '../theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44, this.withText = true});

  final double size;
  final bool withText;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: TmpsColors.gradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: const Color(0x737C6CFF),
            blurRadius: size * 0.5,
            offset: Offset(0, size * 0.18),
          ),
        ],
      ),
      child: TmpsIcon(Ico.box, color: Colors.white, size: size * 0.62, stroke: 1.9),
    );

    if (!withText) return mark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(height: size * 0.28),
        Text(
          'tmps',
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: TmpsColors.text,
          ),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: TmpsColors.surface2,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: TmpsColors.border),
              ),
              child: TmpsIcon(icon, color: TmpsColors.muted, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TmpsColors.text),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: TmpsColors.muted, height: 1.45),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 22),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
