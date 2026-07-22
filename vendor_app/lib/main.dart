import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/routes/app_router.dart';
import 'core/services/realtime_sync.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/presentation/providers/notifications_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  runApp(const ProviderScope(child: VendorApp()));
}

class VendorApp extends ConsumerStatefulWidget {
  const VendorApp({super.key});

  @override
  ConsumerState<VendorApp> createState() => _VendorAppState();
}

class _VendorAppState extends ConsumerState<VendorApp>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialise Realtime subscriptions. Not autoDispose — lives for the
    // ProviderScope lifetime. ref.onDispose inside each provider closes the channel.
    ref.read(vendorRealtimeSyncProvider);
    ref.read(vendorNotificationsRealtimeProvider);
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
        ref.read(vendorRealtimeSyncProvider).refetchAll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'DODO Booker — Vendor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
