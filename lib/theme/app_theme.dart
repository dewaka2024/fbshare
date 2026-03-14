import 'package:flutter/material.dart';

// ─── App-wide colour palette ──────────────────────────────────────────────────

class AppColors {
  // Brand accent – electric indigo
  static const accent = Color(0xFF4F6EF7);
  static const accentDark = Color(0xFF3A55D4);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);

  // Dark surface stack
  static const darkBg = Color(0xFF0F1117);
  static const darkSurface = Color(0xFF1A1D27);
  static const darkCard = Color(0xFF222636);
  static const darkBorder = Color(0xFF2E3347);
  static const darkText = Color(0xFFE8EAF6);
  static const darkSubText = Color(0xFF8B91A8);

  // Light surface stack
  static const lightBg = Color(0xFFF0F2FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF7F8FC);
  static const lightBorder = Color(0xFFDDE1F0);
  static const lightText = Color(0xFF1A1D27);
  static const lightSubText = Color(0xFF6B7280);
}

// ─── ThemeData factories ───────────────────────────────────────────────────────

class AppTheme {
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: AppColors.darkBg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.accentDark,
          surface: AppColors.darkSurface,
          error: AppColors.error,
        ),
        cardColor: AppColors.darkCard,
        dividerColor: AppColors.darkBorder,
        inputDecorationTheme: _inputTheme(dark: true),
        elevatedButtonTheme: _buttonTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkSurface,
          foregroundColor: AppColors.darkText,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.darkText,
            letterSpacing: 0.3,
          ),
        ),
      );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: AppColors.lightBg,
        colorScheme: const ColorScheme.light(
          primary: AppColors.accent,
          secondary: AppColors.accentDark,
          surface: AppColors.lightSurface,
          error: AppColors.error,
        ),
        cardColor: AppColors.lightSurface,
        dividerColor: AppColors.lightBorder,
        inputDecorationTheme: _inputTheme(dark: false),
        elevatedButtonTheme: _buttonTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.lightSurface,
          foregroundColor: AppColors.lightText,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.lightText,
            letterSpacing: 0.3,
          ),
        ),
      );

  static InputDecorationTheme _inputTheme({required bool dark}) =>
      InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.darkCard : AppColors.lightCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: dark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: dark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.accent, width: 1.8),
        ),
        hintStyle: TextStyle(
            color: dark ? AppColors.darkSubText : AppColors.lightSubText,
            fontSize: 14),
      );

  static ElevatedButtonThemeData _buttonTheme() => ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4),
        ),
      );
}
