import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'route_names.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/otp_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/providers/auth_state.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/bookings/presentation/pages/bookings_page.dart';
import '../../features/bookings/presentation/pages/booking_detail_page.dart';
import '../../features/wallet/presentation/pages/wallet_page.dart';
import '../../features/services/presentation/pages/services_page.dart';
import '../../features/services/presentation/pages/add_service_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/documents/presentation/pages/documents_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/subscription/data/subscription_repository.dart';
import '../../features/subscription/domain/models/subscription_plan.dart';
import '../../features/subscription/presentation/pages/subscription_page.dart';
import '../../features/subscription/presentation/pages/browse_plans_page.dart';
import '../../features/subscription/presentation/pages/plan_confirmation_page.dart';
import '../../features/subscription/presentation/pages/payment_page.dart';

// Bridges Riverpod auth state into a Listenable so GoRouter re-evaluates its
// redirect whenever auth state changes (e.g. session restored on cold start).
class _AuthRouterNotifier extends ChangeNotifier {
  _AuthRouterNotifier(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRouterNotifier(ref);

  return GoRouter(
    // Splash is the true first frame. Redirect drives every destination from here.
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      final path = state.matchedLocation;

      return switch (authState) {
        // Stay on splash until auth resolves — prevents Login flash on cold start.
        AuthInitial() || AuthLoading() =>
          path == RoutePaths.splash ? null : RoutePaths.splash,
        // Authenticated: leave auth/splash pages, stay put everywhere else.
        AuthAuthenticated() =>
          (path == RoutePaths.splash ||
                  path == RoutePaths.login ||
                  path == RoutePaths.otp)
              ? RoutePaths.dashboard
              : null,
        // OTP flow: ensure we're on the OTP page.
        AuthOtpSent() => path == RoutePaths.otp ? null : RoutePaths.otp,
        // Unauthenticated / error: go to login unless already on an auth page.
        AuthUnauthenticated() || AuthError() =>
          (path == RoutePaths.login || path == RoutePaths.otp)
              ? null
              : RoutePaths.login,
      };
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (context, state) => const SplashPage(),
      ),
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
        builder: (context, state) {
          final tab =
              int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0;
          return BookingsPage(initialTabIndex: tab);
        },
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
        path: RoutePaths.documents,
        name: RouteNames.documents,
        builder: (context, state) => const DocumentsPage(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        name: RouteNames.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: RoutePaths.subscription,
        name: RouteNames.subscription,
        builder: (context, state) => const SubscriptionPage(),
      ),
      GoRoute(
        path: RoutePaths.browsePlans,
        name: RouteNames.browsePlans,
        builder: (context, state) => const BrowsePlansPage(),
      ),
      GoRoute(
        path: RoutePaths.planConfirmation,
        name: RouteNames.planConfirmation,
        builder: (context, state) {
          final plan = state.extra as SubscriptionPlan;
          return PlanConfirmationPage(plan: plan);
        },
      ),
      GoRoute(
        path: RoutePaths.payment,
        name: RouteNames.payment,
        builder: (context, state) {
          final info = state.extra as PendingPaymentInfo;
          return PaymentPage(info: info);
        },
      ),
    ],
  );
});
