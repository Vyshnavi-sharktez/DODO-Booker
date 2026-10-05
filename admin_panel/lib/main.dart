import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/services/fcm_service.dart';
import 'core/services/realtime_sync.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/providers/auth_provider.dart';
import 'features/auth/domain/models/admin_user.dart';
import 'features/notifications/services/notification_router.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(adminRealtimeSyncProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final adminUser = ref.read(currentAdminUserProvider);
      if (adminUser != null) {
        AdminFcmService.initialize(adminUser.id).catchError((_) {});
      }
      _setupFcmTapListeners();
      _listenForegroundMessages();
    });
  }

  void _setupFcmTapListeners() {
    final router = ref.read(routerProvider);

    // Cold start (mainly mobile; on web returns null)
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null && mounted) {
        AdminNotificationRouter.handleFromPush(router, message.data);
      }
    });

    // Background → foreground
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (mounted) {
        AdminNotificationRouter.handleFromPush(router, message.data);
      }
    });
  }

  void _listenForegroundMessages() {
    AdminFcmService.foregroundStream.listen((message) {
      if (!mounted) return;
      final notification = message.notification;
      if (notification == null) return;
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('${notification.title ?? ''}: ${notification.body ?? ''}'),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
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
      if (paused != null &&
          DateTime.now().difference(paused) > const Duration(minutes: 5)) {
        ref.read(adminRealtimeSyncProvider).refetchAll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    ref.listen<AdminUser?>(currentAdminUserProvider, (previous, next) {
      if (next != null && previous?.id != next.id) {
        AdminFcmService.initialize(next.id).catchError((_) {});
      } else if (next == null && previous != null) {
        AdminFcmService.clearToken(previous.id).catchError((_) {});
      }
    });

    return MaterialApp.router(
      title: 'DODO BOOKER Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      locale: const Locale('en'),
      scaffoldMessengerKey: _messengerKey,
    );
  }
}
