import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/services/fcm_background_handler.dart';
import 'core/services/local_notification_service.dart';
import 'core/theme/theme_provider.dart';
import 'features/home/services/home_providers.dart';
import 'firebase_options.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await LocalNotificationService.initialize();

  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('dodo_theme_mode');
  final initialTheme =
      savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
  final isLoggedIn = prefs.getString('dodo_auth_phone') != null;

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    // ignore: deprecated_member_use
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(
    ProviderScope(
      overrides: [
        themeProvider.overrideWith((ref) => ThemeNotifier(initialTheme)),
        mobileServicesUnlockedProvider.overrideWith((ref) => isLoggedIn),
      ],
      child: const App(),
    ),
  );
}
