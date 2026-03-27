import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF1A1A1A);
  static const surface = Color(0xFF2A2A2A);
  static const surfaceLight = Color(0xFF3A3A3A);
  static const amber = Color(0xFFD4920B);
  static const amberLight = Color(0xFFE8B44C);
  static const ashGrey = Color(0xFFB8B8B8);
  static const textPrimary = Color(0xFFF5F5F5);
  static const textSecondary = Color(0xFF9E9E9E);
  static const smoke = Color(0x33FFFFFF);
  static const danger = Color(0xFFE53935);
  static const success = Color(0xFF43A047);
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.amber,
      secondary: AppColors.amberLight,
      surface: AppColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.amber,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.amber,
      foregroundColor: Colors.white,
    ),
  );
}
