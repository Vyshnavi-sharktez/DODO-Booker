import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/theme_provider.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('dodo_theme_mode');
  final initialTheme =
      savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => ThemeNotifier(initialTheme)),
      ],
      child: const App(),
    ),
  );
}
