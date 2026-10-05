import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/routes/app_router.dart';
import 'core/routes/route_names.dart';
import 'core/services/fcm_background_handler.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/realtime_sync.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/presentation/providers/notifications_provider.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await LocalNotificationService.initialize();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
  );

  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const VendorApp(),
  ));
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
    ref.read(vendorRealtimeSyncProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupFcmTapListeners());
  }

  void _setupFcmTapListeners() {
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null && mounted) {
        _routeFromPush(message.data);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (mounted) _routeFromPush(message.data);
    });
    LocalNotificationService.tapStream.listen((data) {
      if (mounted) _routeFromPush(data);
    });
  }

  void _routeFromPush(Map<String, dynamic> data) {
    final router = ref.read(routerProvider);
    final entityType = data['entity_type'] as String?;
    final entityId = data['entity_id'] as String?;
    final notificationType = data['notification_type'] as String?;
    if ((entityType == 'booking' ||
            notificationType == 'vendor_assigned' ||
            notificationType == 'new_dispatch_offer' ||
            notificationType == 'vendor_reassigned') &&
        entityId != null &&
        entityId.isNotEmpty) {
      router.pushNamed(RouteNames.bookingDetail, pathParameters: {'id': entityId});
    } else if (entityType == 'vendor_wallet' ||
        entityType == 'wallet' ||
        notificationType == 'wallet_low_balance' ||
        notificationType == 'wallet_alert' ||
        notificationType == 'wallet_penalty') {
      router.pushNamed(RouteNames.wallet);
    } else if (entityType == 'vendor_service_request' ||
        notificationType == 'vendor_service_request') {
      router.pushNamed(RouteNames.services, queryParameters: {'tab': '2'});
    } else if (entityType == 'customer_question' ||
        notificationType == 'new_customer_question') {
      router.pushNamed(RouteNames.services,
          queryParameters: {'tab': '0', 'subTab': '2'});
    }
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
