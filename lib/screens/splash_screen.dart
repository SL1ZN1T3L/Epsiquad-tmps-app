import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/brand.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 64),
            SizedBox(height: 22),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: TmpsColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
