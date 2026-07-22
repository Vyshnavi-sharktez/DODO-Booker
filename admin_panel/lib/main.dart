import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/services/realtime_sync.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey, // ignore: deprecated_member_use — still valid for anon key
    debug: false,
  );

  runApp(
    const ProviderScope(
      child: DodoAdminApp(),
    ),
  );
}

class DodoAdminApp extends ConsumerStatefulWidget {
  const DodoAdminApp({super.key});

  @override
  ConsumerState<DodoAdminApp> createState() => _DodoAdminAppState();
}

class _DodoAdminAppState extends ConsumerState<DodoAdminApp>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialise Realtime subscription. Not autoDispose — lives for the
    // ProviderScope lifetime. ref.onDispose inside the provider closes the channel.
    ref.read(adminRealtimeSyncProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final paused = _pausedAt;
      _pausedAt = null;
      // After a long background gap Realtime may have missed events — refetch.
      if (paused != null &&
          DateTime.now().difference(paused) > const Duration(minutes: 5)) {
        ref.read(adminRealtimeSyncProvider).refetchAll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'DODO BOOKER Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
