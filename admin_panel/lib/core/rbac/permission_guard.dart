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
  '/rbac': 'rbac.read',
  '/catalog': 'catalog.read',
  '/categories': 'catalog.read',
  '/sub-categories': 'catalog.read',
  '/services': 'catalog.read',
  '/service-attributes': 'catalog.read',
  '/vendors': 'vendor.read',
  '/dodo-teams': 'dodo_team.read',
  '/bookings': 'booking.read',
  '/customers': 'customer.read',
  '/abandoned-carts': 'customer.read',
  '/coupons': 'coupon.read',
  '/vendor-settlement': 'vendor.read',
  '/settings': 'settings.read',
  '/loyalty': 'settings.read',
  '/tax-settings': 'settings.read',
  '/global-scheduling': 'scheduling.read',
  '/commission': 'settings.read',
  '/vendor-serving-areas': 'vendor.read',
  '/service-availability-areas': 'settings.read',
  '/surge-fees': 'settings.read',
  '/seo': 'settings.read',
  '/landing-page': 'settings.read',
  '/payment-config': 'settings.read',
  '/push-config': 'settings.read',
  '/vendor-subscriptions': 'vendor.read',
  '/vendor-tiers': 'vendor.read',
  '/amc-plans': 'catalog.read',
  '/amc-scheduling-requests': 'booking.read',
  '/warranty-claims': 'booking.read',
  '/warranty-analytics': 'booking.read',
  '/call-sessions': 'booking.read',
  '/dispatch-analytics': 'booking.read',
  '/gps-audit': 'booking.read',
  '/gps-analytics': 'booking.read',
  '/vendor-service-requests': 'vendor.read',
  '/vendor-catalog': 'vendor.read',
  '/refunds': 'refund.view',
  '/support': 'support.read',
  '/notifications': 'notification.read',
};

// Dynamic route patterns: a prefix match maps to its module permission.
// Checked only when no exact entry is found in routePermissions.
const Map<String, String> _dynamicRoutePermissions = {
  '/vendors/': 'vendor.read',
  '/customers/': 'customer.read',
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
    final adminAsync = ref.watch(adminUserProvider);

    // Still fetching — don't redirect. The stream will emit and rebuild.
    if (!adminAsync.hasValue) return const SizedBox.shrink();

    final user = adminAsync.value;
    // Null value means logged out / deactivated; router handles /login redirect.
    if (user == null) return const SizedBox.shrink();

    if (user.hasPermission(permission)) return child;

    if (fallback != null) return fallback!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/unauthorized');
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
    final adminAsync = ref.watch(adminUserProvider);

    if (!adminAsync.hasValue) return const SizedBox.shrink();

    final user = adminAsync.value;
    if (user == null) return const SizedBox.shrink();

    if (user.hasAnyPermission(permissions)) return child;

    if (fallback != null) return fallback!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.go('/unauthorized');
    });
    return const SizedBox.shrink();
  }
}
