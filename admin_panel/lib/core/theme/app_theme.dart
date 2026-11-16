import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Responsive breakpoints used across the admin panel.
class AppBreakpoints {
  static const double mobile = 768;
  static const double tablet = 1024;
}

class AppColors {
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryLight = Color(0xFF2D5282);
  static const Color accent = Color(0xFF4A90D9);
  static const Color background = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color sidebarBg = Color(0xFF1E3A5F);
  static const Color sidebarText = Color(0xFFB0C4DE);
  static const Color sidebarActive = Color(0xFF4A90D9);
  static const Color sidebarActiveText = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color textPrimary = Color(0xFF1A202C);
  static const Color textSecondary = Color(0xFF718096);
  static const Color error = Color(0xFFE53E3E);
  static const Color success = Color(0xFF38A169);
  static const Color warning = Color(0xFFDD6B20);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.error,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: GoogleFonts.inter().fontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
        labelStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      listTileTheme: const ListTileThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 57, fontWeight: FontWeight.w800),
        displayMedium: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 45, fontWeight: FontWeight.w800),
        displaySmall: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 36, fontWeight: FontWeight.w700),
        headlineLarge: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700),
        headlineSmall: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700),
        titleMedium: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w400),
        bodyMedium: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w400),
        bodySmall: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w400),
        labelLarge: GoogleFonts.inter(
          color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
        labelMedium: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
        labelSmall: GoogleFonts.inter(
          color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}

