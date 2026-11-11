import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF9FCFD);
  static const navy = Color(0xFF14324C);
  static const primary = Color(0xFF166D9C);
  static const tint = Color(0xFFE7F4FA);
  static const teal = Color(0xFF138F8A);
  static const mint = Color(0xFFE8F9F3);
  static const muted = Color(0xFF5F7383);
  static const divider = Color(0xFFDFEAF0);
  static const amber = Color(0xFF926025);
  static const cream = Color(0xFFFFF5E8);
  static const red = Color(0xFFB34E54);
  static const rose = Color(0xFFFFF0F1);
}

abstract final class AppSpacing {
  static const small = 8.0;
  static const medium = 16.0;
  static const large = 24.0;
}

abstract final class AppTheme {
  static ThemeData get light {
    final colors = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.background,
      onSurface: AppColors.navy,
      error: AppColors.red,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navy,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.divider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.tint,
      ),
    );
  }
}
