import 'package:flutter/material.dart';

class TmpsColors {
  static const bg = Color(0xFF07080C);
  static const bg2 = Color(0xFF0D0F16);
  static const surface = Color(0xFF12141C);
  static const surface2 = Color(0xFF181B25);
  static const border = Color(0xFF232733);
  static const text = Color(0xFFECEEF4);
  static const muted = Color(0xFF959CAE);
  static const faint = Color(0xFF5F6678);
  static const accent = Color(0xFF7C6CFF);
  static const accent2 = Color(0xFF22D3EE);
  static const ok = Color(0xFF34D399);
  static const warn = Color(0xFFFBBF24);
  static const danger = Color(0xFFFB4B6B);
  static const telegram = Color(0xFF2AABEE);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B7BFF), Color(0xFF5A8CFF), Color(0xFF22D3EE)],
    stops: [0.0, 0.55, 1.0],
  );
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: TmpsColors.accent,
    onPrimary: Colors.white,
    secondary: TmpsColors.accent2,
    onSecondary: Color(0xFF04202A),
    surface: TmpsColors.surface,
    onSurface: TmpsColors.text,
    error: TmpsColors.danger,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: TmpsColors.bg,
    canvasColor: TmpsColors.bg,
    dividerColor: TmpsColors.border,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: TmpsColors.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: TmpsColors.text,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: TmpsColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    cardTheme: CardThemeData(
      color: TmpsColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: TmpsColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TmpsColors.surface2,
      hintStyle: const TextStyle(color: TmpsColors.faint),
      labelStyle: const TextStyle(color: TmpsColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TmpsColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TmpsColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TmpsColors.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TmpsColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: TmpsColors.text,
        side: const BorderSide(color: TmpsColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: TmpsColors.accent),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: TmpsColors.surface2,
      contentTextStyle: const TextStyle(color: TmpsColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: TmpsColors.bg2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: TmpsColors.bg2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: TmpsColors.accent,
      linearTrackColor: TmpsColors.surface2,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: TmpsColors.muted,
      textColor: TmpsColors.text,
    ),
  );
}
