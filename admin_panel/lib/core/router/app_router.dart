import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/application/providers/auth_provider.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/reset_password_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_shell.dart';
import '../../features/dashboard/presentation/pages/dashboard_home_page.dart';
import '../../features/rbac/presentation/pages/rbac_page.dart';
import '../../features/categories/presentation/pages/categories_page.dart';
import '../../features/sub_categories/presentation/pages/sub_categories_page.dart';
import '../../features/services/presentation/pages/services_page.dart';
import '../../features/service_attributes/presentation/pages/service_attributes_page.dart';
import '../../features/vendors/presentation/pages/vendors_page.dart';
import '../../features/dodo_teams/presentation/pages/dodo_teams_page.dart';
import '../../features/vendors/presentation/pages/vendor_details_page.dart';
import '../../features/bookings/presentation/pages/bookings_page.dart';
import '../../features/customers/presentation/pages/customers_page.dart';
import '../../features/customers/presentation/pages/customer_profile_page.dart';
import '../../features/coupons/presentation/pages/coupons_page.dart';
import '../../features/vendor_settlement/presentation/pages/vendor_settlement_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/catalog_v2/presentation/pages/catalog_v2_page.dart';
import '../../features/service_addons/presentation/pages/addons_page.dart';
import '../../features/marketing/presentation/pages/abandoned_carts_page.dart';
import '../../features/loyalty/presentation/pages/loyalty_page.dart';
import '../../features/tax_settings/presentation/pages/tax_settings_page.dart';
import '../../features/global_scheduling/presentation/pages/global_scheduling_page.dart';
import '../../features/commission/presentation/pages/commission_settings_page.dart';
import '../../features/vendor_serving_areas/presentation/pages/vendor_serving_areas_page.dart';
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
    // /reset-password is public: the Supabase recovery session makes the user
    // technically "logged in", and we must not redirect them away from it.
    final bool isOnResetPage = location == '/reset-password';

    if (!isLoggedIn && !isOnLoginPage && !isOnResetPage) return '/login';
    if (isLoggedIn && isOnLoginPage) return '/dashboard';
    // Never redirect away from /reset-password (recovery session is active).

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
      GoRoute(
        path: '/reset-password',
        name: 'resetPassword',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: ResetPasswordPage(),
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
            path: '/dashboard/catalog',
            name: 'catalog',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CatalogV2Page(),
            ),
          ),
          GoRoute(
            path: '/dashboard/addons',
            name: 'addons',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AddonsPage(),
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
            pageBuilder: (context, state) => NoTransitionPage(
              child: SubCategoriesPage(
                filterCategoryId:
                    state.uri.queryParameters['categoryId'],
              ),
            ),
          ),
          GoRoute(
            path: '/dashboard/services',
            name: 'services',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ServicesPage(
                filterSubCategoryId:
                    state.uri.queryParameters['subCategoryId'],
              ),
            ),
          ),
          GoRoute(
            path: '/dashboard/service-attributes',
            name: 'serviceAttributes',
            pageBuilder: (context, state) => NoTransitionPage(
              child: ServiceAttributesPage(
                filterServiceId:
                    state.uri.queryParameters['serviceId'],
              ),
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
            path: '/dashboard/dodo-teams',
            name: 'dodoTeams',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DodoTeamsPage(),
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
            path: '/dashboard/customers/:customerId',
            name: 'customerProfile',
            pageBuilder: (context, state) => NoTransitionPage(
              child: CustomerProfilePage(
                customerId: state.pathParameters['customerId']!,
              ),
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
            path: '/dashboard/settings',
            name: 'settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/loyalty',
            name: 'loyalty',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: LoyaltyPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/tax-settings',
            name: 'taxSettings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TaxSettingsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/global-scheduling',
            name: 'globalScheduling',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: GlobalSchedulingPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/commission',
            name: 'commission',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: CommissionSettingsPage(),
            ),
          ),
          GoRoute(
            path: '/dashboard/vendor-serving-areas',
            name: 'vendorServingAreas',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: VendorServingAreasPage(),
            ),
          ),
        ],
      ),
    ],
  );
});
