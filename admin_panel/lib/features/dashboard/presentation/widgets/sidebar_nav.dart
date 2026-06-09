import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/rbac/permission_guard.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.route,
    this.requiredPermission,
  });
  final String label;
  final IconData icon;
  final String route;
  // null = always visible (Dashboard)
  final String? requiredPermission;
}

const _navItems = <_NavItem>[
  _NavItem(
    label: 'Dashboard',
    icon: Icons.dashboard_rounded,
    route: '/dashboard',
  ),
  _NavItem(
    label: 'RBAC',
    icon: Icons.admin_panel_settings_rounded,
    route: '/dashboard/rbac',
    requiredPermission: 'rbac.manage',
  ),
  _NavItem(
    label: 'Categories',
    icon: Icons.category_rounded,
    route: '/dashboard/categories',
    requiredPermission: 'category.view',
  ),
  _NavItem(
    label: 'Sub Categories',
    icon: Icons.list_alt_rounded,
    route: '/dashboard/sub-categories',
    requiredPermission: 'category.view',
  ),
  _NavItem(
    label: 'Services',
    icon: Icons.home_repair_service_rounded,
    route: '/dashboard/services',
    requiredPermission: 'service.view',
  ),
  _NavItem(
    label: 'Service Attributes',
    icon: Icons.tune_rounded,
    route: '/dashboard/service-attributes',
    requiredPermission: 'service.view',
  ),
  _NavItem(
    label: 'Vendors',
    icon: Icons.store_rounded,
    route: '/dashboard/vendors',
    requiredPermission: 'vendor.view',
  ),
  _NavItem(
    label: 'Bookings',
    icon: Icons.book_online_rounded,
    route: '/dashboard/bookings',
    requiredPermission: 'booking.view',
  ),
  _NavItem(
    label: 'Customers',
    icon: Icons.people_rounded,
    route: '/dashboard/customers',
    requiredPermission: 'customer.view',
  ),
  _NavItem(
    label: 'Coupons',
    icon: Icons.local_offer_rounded,
    route: '/dashboard/coupons',
    requiredPermission: 'coupon.view',
  ),
  _NavItem(
    label: 'Settings',
    icon: Icons.settings_rounded,
    route: '/dashboard/settings',
    requiredPermission: 'settings.manage',
  ),
];

class SidebarNav extends ConsumerWidget {
  const SidebarNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final adminUser = ref.watch(currentAdminUserProvider);

    final visibleItems = _navItems.where((item) {
      if (item.requiredPermission == null) return true;
      return ref.watch(hasPermissionProvider(item.requiredPermission!));
    }).toList();

    return Container(
      width: 250,
      color: AppColors.sidebarBg,
      child: Column(
        children: [
          // ── Brand ──────────────────────────────────────────────────────────
          _SidebarBrand(),

          // ── Navigation items ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'MAIN MENU',
                    style: TextStyle(
                      color: Color(0xFF4A6FA5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                for (final item in visibleItems)
                  _NavTile(
                    item: item,
                    isActive: _isActive(location, item.route),
                  ),
              ],
            ),
          ),

          // ── User info + Logout ─────────────────────────────────────────────
          _SidebarFooter(
            displayName: adminUser?.displayName ?? 'Admin',
            role: adminUser?.primaryRole ?? '',
            onLogout: () async {
              await ref.read(authNotifierProvider.notifier).logout();
            },
          ),
        ],
      ),
    );
  }

  bool _isActive(String location, String route) {
    if (route == '/dashboard') return location == '/dashboard';
    return location.startsWith(route);
  }
}

class _SidebarBrand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF2D5282), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DODO BOOKER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Admin Panel',
                  style: TextStyle(
                    color: Color(0xFF6B8EB5),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({required this.item, required this.isActive});
  final _NavItem item;
  final bool isActive;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(widget.item.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.18)
                : _hovered
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: AppColors.accent.withValues(alpha: 0.4))
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(
                widget.item.icon,
                size: 18,
                color: active
                    ? AppColors.sidebarActiveText
                    : AppColors.sidebarText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.item.label,
                  style: TextStyle(
                    color: active
                        ? AppColors.sidebarActiveText
                        : AppColors.sidebarText,
                    fontSize: 13.5,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (active)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.displayName,
    required this.role,
    required this.onLogout,
  });

  final String displayName;
  final String role;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF2D5282), width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (role.isNotEmpty)
                      Text(
                        role,
                        style: const TextStyle(
                          color: Color(0xFF6B8EB5),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LogoutButton(onLogout: onLogout),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatefulWidget {
  const _LogoutButton({required this.onLogout});
  final VoidCallback onLogout;

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onLogout,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.error.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.logout_rounded,
                size: 16,
                color: _hovered ? AppColors.error : const Color(0xFF6B8EB5),
              ),
              const SizedBox(width: 8),
              Text(
                'Sign Out',
                style: TextStyle(
                  color: _hovered ? AppColors.error : const Color(0xFF6B8EB5),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
