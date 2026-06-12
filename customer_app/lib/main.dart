import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only initialise when credentials are provided via --dart-define.
  // Without credentials the app runs with the dev fallback dataset.
   {
    await Supabase.initialize(
      url: 'https://qspilpbvcldgelgwwrdr.supabase.co',
      // ignore: deprecated_member_use
      anonKey: 'sb_publishable_6jGP7zViURbDBG-PiwsoJg_7FQSfeWz',
    );
  }

  runApp(const ProviderScope(child: App()));
}
