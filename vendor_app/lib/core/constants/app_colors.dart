import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFF1A73E8);
  static const Color primaryLight = Color(0xFFE8F0FE);
  static const Color accent = Color(0xFF34A853);

  // Semantic
  static const Color success = Color(0xFF34A853);
  static const Color warning = Color(0xFFFBBC04);
  static const Color error = Color(0xFFEA4335);
  static const Color info = Color(0xFF4285F4);

  // Neutral
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8F9FA);
  static const Color border = Color(0xFFE0E0E0);

  // Text
  static const Color textPrimary = Color(0xFF202124);
  static const Color textSecondary = Color(0xFF5F6368);
  static const Color textHint = Color(0xFF9AA0A6);

  // Booking status
  static const Color statusPending = Color(0xFFFBBC04);
  static const Color statusAssigned = Color(0xFF4285F4);
  static const Color statusInProgress = Color(0xFF9C27B0);
  static const Color statusCompleted = Color(0xFF34A853);
  static const Color statusCancelled = Color(0xFFEA4335);
}
