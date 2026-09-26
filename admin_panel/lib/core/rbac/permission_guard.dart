import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/application/providers/auth_provider.dart';

// ── Permission check providers ─────────────────────────────────────────────────

final hasPermissionProvider = Provider.family<bool, String>((ref, key) {
  final user = ref.watch(currentAdminUserProvider);
  if (user == null) return false;
  return user.hasPermission(key);
});

final hasAnyPermissionProvider =
    Provider.family<bool, List<String>>((ref, keys) {
  final user = ref.watch(currentAdminUserProvider);
  if (user == null) return false;
  return user.hasAnyPermission(keys);
});

// ── Route permission map ───────────────────────────────────────────────────────
// Maps stripped route paths (without /dashboard prefix) to required permissions.
// Dynamic routes like /vendors/:id are handled separately in resolveRoutePermission.

const Map<String, String> routePermissions = {
  '/rbac': 'rbac.manage',
  '/catalog': 'category.view',
  '/addons': 'category.view',
  '/categories': 'category.view',
  '/sub-categories': 'category.view',
  '/services': 'service.view',
  '/service-attributes': 'service.view',
  '/vendors': 'vendor.view',
  '/dodo-teams': 'dodo_team.view',
  '/bookings': 'booking.view',
  '/customers': 'customer.view',
  '/abandoned-carts': 'customer.view',
  '/coupons': 'coupon.view',
  '/vendor-settlement': 'vendor.view',
  '/settings': 'settings.manage',
  '/loyalty': 'settings.manage',
  '/tax-settings': 'settings.manage',
  '/global-scheduling': 'settings.manage',
  '/commission': 'settings.manage',
  '/vendor-serving-areas': 'vendor.view',
  '/service-availability-areas': 'settings.manage',
  '/surge-fees': 'settings.manage',
  '/seo': 'settings.manage',
  '/landing-page': 'settings.manage',
  '/payment-config': 'settings.manage',
  '/vendor-subscriptions': 'vendor.view',
  '/vendor-tiers': 'vendor.view',
  '/amc-plans': 'category.view',
  '/amc-scheduling-requests': 'booking.view',
  '/warranty-claims': 'booking.view',
  '/warranty-analytics': 'booking.view',
  '/call-sessions': 'booking.view',
  '/dispatch-analytics': 'booking.view',
  '/gps-audit': 'booking.view',
  '/gps-analytics': 'booking.view',
  '/vendor-service-requests': 'vendor.view',
  '/vendor-catalog': 'vendor.view',
  '/refunds': 'refund.view',
  '/support': 'booking.view',
};

// Dynamic route patterns: a prefix match maps to its module permission.
// Checked only when no exact entry is found in routePermissions.
const Map<String, String> _dynamicRoutePermissions = {
  '/vendors/': 'vendor.view',
  '/customers/': 'customer.view',
};

/// Returns the required permission for [strippedPath], or null if the route
/// is open to all authenticated admins.
String? resolveRoutePermission(String strippedPath) {
  final exact = routePermissions[strippedPath];
  if (exact != null) return exact;
  for (final entry in _dynamicRoutePermissions.entries) {
    if (strippedPath.startsWith(entry.key)) return entry.value;
  }
  return null;
}

// ── Permission guard widget ────────────────────────────────────────────────────

class PermissionGuard extends ConsumerWidget {
  final String permission;
  final Widget child;
  final Widget? fallback;

  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(hasPermissionProvider(permission));
    if (allowed) return child;
    if (fallback != null) return fallback!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/unauthorized');
    });
    return const SizedBox.shrink();
  }
}

// ── Any-permission guard widget ────────────────────────────────────────────────

class AnyPermissionGuard extends ConsumerWidget {
  final List<String> permissions;
  final Widget child;
  final Widget? fallback;

  const AnyPermissionGuard({
    super.key,
    required this.permissions,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(hasAnyPermissionProvider(permissions));
    if (allowed) return child;
    if (fallback != null) return fallback!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/unauthorized');
    });
    return const SizedBox.shrink();
  }
}
