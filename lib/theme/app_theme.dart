import 'package:flutter/material.dart';

/// Claude-inspired warm, paper-like color palette.
/// The whole design language avoids cold corporate blues/grays and
/// leans on a cream/terracotta pairing similar to Claude's own apps.
class AppColors {
  AppColors._();

  // Light mode
  static const Color lightBackground = Color(0xFFFAF7F2); // warm cream
  static const Color lightSurface = Color(0xFFF3EDE4); // slightly deeper cream (cards, bubbles)
  static const Color lightSurfaceAlt = Color(0xFFEDE6D9); // input bar / sidebar
  static const Color lightBorder = Color(0xFFE2D9C8);
  static const Color lightTextPrimary = Color(0xFF2B2621); // warm near-black
  static const Color lightTextSecondary = Color(0xFF7A7267);

  // Dark mode
  static const Color darkBackground = Color(0xFF262220); // warm dark brown, not pure black
  static const Color darkSurface = Color(0xFF322C28);
  static const Color darkSurfaceAlt = Color(0xFF3A332E);
  static const Color darkBorder = Color(0xFF463E37);
  static const Color darkTextPrimary = Color(0xFFF3ECE3);
  static const Color darkTextSecondary = Color(0xFFAA9F92);

  // Brand accent - terracotta/coral, used sparingly for actions & emphasis
  static const Color accent = Color(0xFFD97757);
  static const Color accentDark = Color(0xFFC15F3C);
  static const Color accentSoft = Color(0xFFF1DDD1); // light tint for selected chips, user bubble
  static const Color accentSoftDark = Color(0xFF4A362E); // dark-mode tint of accent

  static const Color error = Color(0xFFC1544B);
}

class AppTheme {
  AppTheme._();

  static const double radiusSmall = 10;
  static const double radiusMedium = 16;
  static const double radiusLarge = 24;

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        secondary: AppColors.accentDark,
        surface: AppColors.lightSurface,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        foregroundColor: AppColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.lightTextPrimary,
        displayColor: AppColors.lightTextPrimary,
      ),
      dividerColor: AppColors.lightBorder,
      iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.lightSurfaceAlt,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide.none,
        ),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.darkBackground,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        secondary: AppColors.accentDark,
        surface: AppColors.darkSurface,
        error: AppColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.darkTextPrimary,
        displayColor: AppColors.darkTextPrimary,
      ),
      dividerColor: AppColors.darkBorder,
      iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.darkSurfaceAlt,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide.none,
        ),
      ),
      useMaterial3: true,
    );
  }
}
