import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/local_notification_service.dart';
import 'core/services/realtime_sync.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/notifications/services/notification_router.dart';
import 'routes/app_router.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(realtimeSyncProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupFcmTapListeners());
  }

  void _setupFcmTapListeners() {
    // Cold start: app was fully closed when notification was tapped
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null && mounted) {
        CustomerNotificationRouter.handleFromPush(context, ref, message.data);
      }
    });

    // Background → foreground: app was in background when notification was tapped
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (mounted) {
        CustomerNotificationRouter.handleFromPush(context, ref, message.data);
      }
    });

    // Foreground: user tapped local notification shown while app was open
    LocalNotificationService.tapStream.listen((data) {
      if (mounted) {
        CustomerNotificationRouter.handleFromPush(context, ref, data);
      }
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
        ref.read(realtimeSyncProvider).refetchAll();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'DODO Booker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
