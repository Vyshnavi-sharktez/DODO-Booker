import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'dodo_theme_mode';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier(super.initial);

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(ThemeMode.light),
);
