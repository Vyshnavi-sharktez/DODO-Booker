import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Brand primaries (Ink #1A1714) ────────────────────────────────────────────
  static const Color primary = Color(0xFF1A1714);
  static const Color primaryDark = Color(0xFF000000);
  static const Color primaryLight = Color(0xFFE8E4DF);

  // ── Gold accent ─────────────────────────────────────────────────────────────
  static const Color gold = Color(0xFFF4A81D);
  static const Color goldDeep = Color(0xFFD98A0A);
  static const Color goldLight = Color(0xFFFDF2D9);

  // ── Secondary ───────────────────────────────────────────────────────────────
  static const Color secondary = Color(0xFFFF6D00);
  static const Color secondaryLight = Color(0xFFFFE0B2);

  // ── Backgrounds ─────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFFBF8F3);    // Warm White
  static const Color surface = Color(0xFFFFFFFF);        // Card White
  static const Color surfaceVariant = Color(0xFFF5EFE6); // Warm light variant

  // ── Text ────────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A1714);   // Ink
  static const Color textSecondary = Color(0xFF6E6A64); // Text Muted
  static const Color textHint = Color(0xFF8F8A82);      // Why Choose Gray

  // ── Status ──────────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF34A853);
  static const Color warning = Color(0xFFFBBC04);
  static const Color error = Color(0xFFEA4335);

  // ── Borders / dividers ──────────────────────────────────────────────────────
  static const Color divider = Color(0xFFECE7DE);
  static const Color border = Color(0xFFECE7DE);

  // ── How It Works step colors ─────────────────────────────────────────────────
  static const Color stepGold = Color(0xFFF0B429);
  static const Color stepTeal = Color(0xFF4FA394);
  static const Color stepCoral = Color(0xFFE2735A);
  static const Color stepBrown = Color(0xFF6B4A38);

  // ── Skeleton ────────────────────────────────────────────────────────────────
  static const Color shimmerBase = Color(0xFFECE7DE);
  static const Color shimmerHighlight = Color(0xFFF5EFE6);
}
