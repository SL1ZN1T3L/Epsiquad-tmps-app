import 'package:flutter/material.dart';

import '../theme.dart';

class DialogActions extends StatelessWidget {
  const DialogActions({super.key, required this.children});

  final List<Widget> children;

  static ButtonStyle primaryStyle(BuildContext context) => const ButtonStyle();

  static ButtonStyle dangerStyle(BuildContext context) => TextButton.styleFrom(
        foregroundColor: TmpsColors.dangerSoft,
        side: const BorderSide(color: TmpsColors.dangerSoft, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Align(
            alignment: Alignment.center,
            child: children[i],
          ),
        ],
      ],
    );
  }
}
