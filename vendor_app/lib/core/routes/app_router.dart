import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'route_names.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/otp_page.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/providers/auth_state.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/bookings/presentation/pages/bookings_page.dart';
import '../../features/bookings/presentation/pages/booking_detail_page.dart';
import '../../features/wallet/presentation/pages/wallet_page.dart';
import '../../features/services/presentation/pages/services_page.dart';
import '../../features/services/presentation/pages/add_service_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RoutePaths.login,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final path = state.matchedLocation;
      final onAuthPage = path == RoutePaths.login || path == RoutePaths.otp;

      return switch (authState) {
        AuthInitial() || AuthLoading() => null,
        AuthAuthenticated() => onAuthPage ? RoutePaths.dashboard : null,
        AuthOtpSent() => path == RoutePaths.login ? RoutePaths.otp : null,
        AuthUnauthenticated() || AuthError() => !onAuthPage ? RoutePaths.login : null,
      };
    },
    routes: [
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: RoutePaths.otp,
        name: RouteNames.otp,
        builder: (context, state) => const OtpPage(),
      ),
      GoRoute(
        path: RoutePaths.dashboard,
        name: RouteNames.dashboard,
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: RoutePaths.bookings,
        name: RouteNames.bookings,
        builder: (context, state) => const BookingsPage(),
      ),
      GoRoute(
        path: RoutePaths.bookingDetail,
        name: RouteNames.bookingDetail,
        builder: (context, state) => BookingDetailPage(
          bookingId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: RoutePaths.wallet,
        name: RouteNames.wallet,
        builder: (context, state) => const WalletPage(),
      ),
      GoRoute(
        path: RoutePaths.services,
        name: RouteNames.services,
        builder: (context, state) => const ServicesPage(),
      ),
      GoRoute(
        path: RoutePaths.addService,
        name: RouteNames.addService,
        builder: (context, state) => const AddServicePage(),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        name: RouteNames.notifications,
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: RoutePaths.profile,
        name: RouteNames.profile,
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        name: RouteNames.settings,
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
});
