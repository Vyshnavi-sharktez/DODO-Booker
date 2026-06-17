import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/application/providers/auth_provider.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_shell.dart';
import '../../features/dashboard/presentation/pages/dashboard_home_page.dart';
import '../../features/rbac/presentation/pages/rbac_page.dart';
import '../../features/categories/presentation/pages/categories_page.dart';
import '../../features/sub_categories/presentation/pages/sub_categories_page.dart';
import '../../features/services/presentation/pages/services_page.dart';
import '../../features/service_attributes/presentation/pages/service_attributes_page.dart';
import '../../features/vendors/presentation/pages/vendors_page.dart';
import '../../features/vendors/presentation/pages/vendor_details_page.dart';
import '../../features/bookings/presentation/pages/bookings_page.dart';
import '../../features/customers/presentation/pages/customers_page.dart';
import '../../features/coupons/presentation/pages/coupons_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/vendor_assignment/presentation/pages/vendor_assignment_page.dart';
import '../../features/pricing_engine/presentation/pages/pricing_engine_page.dart';
import '../../features/vendor_settlement/presentation/pages/vendor_settlement_page.dart';
import '../../features/cms/presentation/pages/cms_pages_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/marketing/presentation/pages/abandoned_carts_page.dart';
import '../../shared/pages/unauthorized_page.dart';
import '../rbac/permission_guard.dart';

// ── Router refresh listenable that reacts to Supabase auth events ─────────────

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ── Router notifier — owns redirect logic ─────────────────────────────────────

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<AuthState>>(
      authStateProvider,
      (_, next) => notifyListeners(),
    );
    _ref.listen<AsyncValue<dynamic>>(
      adminUserProvider,
      (_, next) => notifyListeners(),
    );
  }

  String? redirect(BuildContext context, GoRouterState state) {
    final authValue = _ref.read(authStateProvider);

    // During initial stream setup fall back to synchronous session check.
    final bool isLoggedIn = authValue.whenOrNull(
          data: (s) => s.session != null,
        ) ??
        (Supabase.instance.client.auth.currentSession != null);

    final location = state.matchedLocation;
    final bool isOnLoginPage = location == '/login';

    if (!isLoggedIn && !isOnLoginPage) return '/login';
    if (isLoggedIn && isOnLoginPage) return '/dashboard';

    // Permission check for protected routes (skip for dashboard and unauthorized).
    if (isLoggedIn && !isOnLoginPage && location != '/dashboard' &&
        location != '/unauthorized') {
      final requiredPermission = routePermissions[_stripDashboardPrefix(location)];
      if (requiredPermission != null) {
        final adminUser = _ref.read(currentAdminUserProvider);
        // While user data is loading, allow through — guard will react when ready.
        if (adminUser != null && !adminUser.hasPermission(requiredPermission)) {
          return '/unauthorized';
        }
      }
    }

    return null;
  }

  String _stripDashboardPrefix(String location) {
    if (location.startsWith('/dashboard/')) {
      return location.replaceFirst('/dashboard', '');
    }
    return location;
  }
}

final routerNotifierProvider = ChangeNotifierProvider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

// ── GoRouter provider ─────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: false,
    refreshListenable: _GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    redirect: notifier.redirect,
    routes: [
      // ── Public ──────────────────────────────────────────────────────────────
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: LoginPage(),
        ),
      ),

      // ── Authenticated shell ──────────────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => DashboardShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardHomePage(),
            ),
          ),
          GoRoute(
            path: '/unauthorized',
            name: 'unauthorized',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: UnauthorizedPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/rbac',
            name: 'rbac',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: RbacPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/categories',
            name: 'categories',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CategoriesPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/sub-categories',
            name: 'subCategories',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SubCategoriesPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/services',
            name: 'services',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ServicesPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/service-attributes',
            name: 'serviceAttributes',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ServiceAttributesPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/vendors',
            name: 'vendors',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: VendorsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/vendors/:vendorId',
            name: 'vendorDetails',
            pageBuilder: (context, state) => NoTransitionPage(
              child: VendorDetailsPage(
                vendorId: state.pathParameters['vendorId']!,
              ),
            ),
          ),
          GoRoute(
            path: '/dashboard/bookings',
            name: 'bookings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: BookingsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/customers',
            name: 'customers',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CustomersPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/coupons',
            name: 'coupons',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CouponsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/pricing-engine',
            name: 'pricingEngine',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PricingEnginePage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/vendor-assignment',
            name: 'vendorAssignment',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: VendorAssignmentPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/notifications',
            name: 'notifications',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: NotificationsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/vendor-settlement',
            name: 'vendorSettlement',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: VendorSettlementPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/abandoned-carts',
            name: 'abandonedCarts',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AbandonedCartsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/cms',
            name: 'cms',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CmsPagesPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/settings',
            name: 'settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsPage(),
            ),
          ),
        ],
      ),
    ],
  );
});
