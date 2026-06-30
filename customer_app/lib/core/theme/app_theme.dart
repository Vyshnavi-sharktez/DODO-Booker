import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

class AppTheme {
  AppTheme._();

  // ── Dark palette constants (only used within darkTheme) ─────────────────────
  static const _darkBg            = Color(0xFF121212);
  static const _darkSurface       = Color(0xFF1E1E1E);
  static const _darkSurfaceVar    = Color(0xFF2C2C2C);
  static const _darkTextPrimary   = Color(0xFFEEEEEE);
  static const _darkTextSecondary = Color(0xFFAAAAAA);
  static const _darkTextHint      = Color(0xFF888888);
  static const _darkBorder        = Color(0xFF383838);
  static const _darkGoldContainer = Color(0xFF3D3000);

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.secondaryLight,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceVariant,
      error: AppColors.error,
      brightness: Brightness.light,
    );

    return _buildTheme(colorScheme: colorScheme, scaffoldBg: AppColors.background);
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.gold,
      onPrimary: const Color(0xFF1A1400),
      primaryContainer: _darkGoldContainer,
      onPrimaryContainer: AppColors.gold,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFF5D2900),
      onSecondaryContainer: const Color(0xFFFFDBCA),
      tertiary: const Color(0xFF80CBC4),
      onTertiary: const Color(0xFF003733),
      tertiaryContainer: const Color(0xFF00504A),
      onTertiaryContainer: const Color(0xFF9EF2EA),
      error: const Color(0xFFFF6B6B),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: _darkSurface,
      onSurface: _darkTextPrimary,
      onSurfaceVariant: _darkTextSecondary,
      outline: _darkBorder,
      outlineVariant: _darkBorder,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: _darkTextPrimary,
      onInverseSurface: _darkBg,
      inversePrimary: const Color(0xFF7B6000),
      surfaceContainerHighest: _darkSurfaceVar,
      surfaceTint: AppColors.gold,
    );

    return _buildTheme(colorScheme: colorScheme, scaffoldBg: _darkBg, isDark: true);
  }

  // ── Shared builder ──────────────────────────────────────────────────────────

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBg,
    bool isDark = false,
  }) {
    final textPrimary   = isDark ? _darkTextPrimary   : AppColors.textPrimary;
    final textSecondary = isDark ? _darkTextSecondary : AppColors.textSecondary;
    final textHint      = isDark ? _darkTextHint      : AppColors.textHint;
    final surfaceBg     = isDark ? _darkSurface       : AppColors.surface;
    final surfaceVar    = isDark ? _darkSurfaceVar    : AppColors.surfaceVariant;
    final borderColor   = isDark ? _darkBorder        : AppColors.border;
    final dividerColor  = isDark ? _darkBorder        : AppColors.divider;
    final navIndicator  = isDark ? _darkGoldContainer : AppColors.primaryLight;
    final navSelected   = isDark ? AppColors.gold     : AppColors.primary;

    final overlayStyle = isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    final primary = colorScheme.primary;
    final errorColor = colorScheme.error;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceBg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        iconTheme: IconThemeData(color: textPrimary),
        systemOverlayStyle: overlayStyle,
      ),

      // ── List tiles ──────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        mouseCursor: WidgetStateMouseCursor.clickable,
      ),

      // ── Bottom Navigation Bar ────────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceBg,
        elevation: 8,
        shadowColor: Colors.black26,
        indicatorColor: navIndicator,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: navSelected, size: 24);
          }
          return IconThemeData(color: textSecondary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: navSelected,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w400,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 68,
      ),

      // ── Card ────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: surfaceBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 0.8),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Dialog ──────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // ── Buttons ─────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(double.infinity, 52),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 52),
          side: BorderSide(color: primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      // ── Input Fields ────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVar,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: errorColor, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: errorColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: TextStyle(color: textHint, fontSize: 14),
        labelStyle: TextStyle(color: textSecondary, fontSize: 14),
        errorStyle: TextStyle(color: errorColor, fontSize: 12),
      ),

      // ── Chip ────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVar,
        selectedColor: navIndicator,
        labelStyle: TextStyle(fontSize: 13, color: textPrimary),
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),

      // ── SnackBar ────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? surfaceBg : AppColors.textPrimary,
        contentTextStyle: TextStyle(
          color: isDark ? textPrimary : Colors.white,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ── Divider ────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 0.8,
        space: 1,
      ),

      // ── Bottom Sheet ────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // ── Typography ──────────────────────────────────────────────────────
      textTheme: TextTheme(
        displayLarge: TextStyle(
          color: textPrimary,
          fontSize: 57,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        displayMedium: TextStyle(
          color: textPrimary,
          fontSize: 45,
          fontWeight: FontWeight.w700,
        ),
        displaySmall: TextStyle(
          color: textPrimary,
          fontSize: 36,
          fontWeight: FontWeight.w600,
        ),
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        titleSmall: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: textHint,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        labelMedium: TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
        labelSmall: TextStyle(
          color: textHint,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
