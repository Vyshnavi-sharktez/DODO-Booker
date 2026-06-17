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

const Map<String, String> routePermissions = {
  '/rbac': 'rbac.manage',
  '/categories': 'category.view',
  '/sub-categories': 'category.view',
  '/services': 'service.view',
  '/service-attributes': 'service.view',
  '/vendors': 'vendor.view',
  '/bookings': 'booking.view',
  '/customers': 'customer.view',
  '/abandoned-carts': 'customer.view',
  '/coupons': 'coupon.view',
  '/notifications': 'notification.view',
  '/vendor-assignment': 'booking.view',
  '/pricing-engine': 'service.view',
  '/vendor-settlement': 'vendor.view',
  '/cms': 'cms.manage',
  '/settings': 'settings.manage',
};

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
