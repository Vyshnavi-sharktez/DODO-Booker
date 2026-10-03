import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/rbac/permission_guard.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';

// ── Data models ──────────────────────────────────────────────────────────────

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
  final String? requiredPermission;
}

class _NavGroup {
  const _NavGroup({
    required this.label,
    required this.icon,
    required this.children,
  });
  final String label;
  final IconData icon;
  final List<_NavItem> children;
}

// ── Dashboard (standalone direct item) ───────────────────────────────────────

const _kDashboard = _NavItem(
  label: 'Dashboard',
  icon: Icons.dashboard_rounded,
  route: '/dashboard',
);

// ── Grouped navigation structure ─────────────────────────────────────────────

const _kNavGroups = <_NavGroup>[
  _NavGroup(
    label: 'Admin Management',
    icon: Icons.admin_panel_settings_rounded,
    children: [
      _NavItem(
        label: 'RBAC',
        icon: Icons.admin_panel_settings_rounded,
        route: '/dashboard/rbac',
        requiredPermission: 'rbac.manage',
      ),
    ],
  ),
  _NavGroup(
    label: 'Catalog',
    icon: Icons.layers_rounded,
    children: [
      _NavItem(
        label: 'Catalog',
        icon: Icons.layers_rounded,
        route: '/dashboard/catalog',
        requiredPermission: 'category.view',
      ),
      _NavItem(
        label: 'Service Areas',
        icon: Icons.map_rounded,
        route: '/dashboard/service-availability-areas',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'AMC Plans',
        icon: Icons.auto_mode_rounded,
        route: '/dashboard/amc-plans',
        requiredPermission: 'category.view',
      ),
    ],
  ),
  _NavGroup(
    label: 'Bookings',
    icon: Icons.book_online_rounded,
    children: [
      _NavItem(
        label: 'Bookings',
        icon: Icons.book_online_rounded,
        route: '/dashboard/bookings',
        requiredPermission: 'booking.view',
      ),
      _NavItem(
        label: 'AMC Requests',
        icon: Icons.schedule_send_rounded,
        route: '/dashboard/amc-scheduling-requests',
        requiredPermission: 'booking.view',
      ),
      _NavItem(
        label: 'Refund Requests',
        icon: Icons.assignment_return_rounded,
        route: '/dashboard/refunds',
        requiredPermission: 'refund.view',
      ),
      _NavItem(
        label: 'Warranty Claims',
        icon: Icons.shield_rounded,
        route: '/dashboard/warranty-claims',
        requiredPermission: 'booking.view',
      ),
    ],
  ),
  _NavGroup(
    label: 'Vendors',
    icon: Icons.store_rounded,
    children: [
      _NavItem(
        label: 'All Vendors',
        icon: Icons.store_rounded,
        route: '/dashboard/vendors',
        requiredPermission: 'vendor.view',
      ),
      _NavItem(
        label: 'DODO Teams',
        icon: Icons.groups_rounded,
        route: '/dashboard/dodo-teams',
        requiredPermission: 'dodo_team.view',
      ),
      _NavItem(
        label: 'Vendor Serving Areas',
        icon: Icons.location_on_rounded,
        route: '/dashboard/vendor-serving-areas',
        requiredPermission: 'vendor.view',
      ),
      _NavItem(
        label: 'Vendor Payouts',
        icon: Icons.account_balance_wallet_rounded,
        route: '/dashboard/vendor-settlement',
        requiredPermission: 'vendor.view',
      ),
      _NavItem(
        label: 'Service Requests',
        icon: Icons.post_add_rounded,
        route: '/dashboard/vendor-service-requests',
        requiredPermission: 'vendor.view',
      ),
      _NavItem(
        label: 'Vendor Catalog',
        icon: Icons.storefront_rounded,
        route: '/dashboard/vendor-catalog',
        requiredPermission: 'vendor.view',
      ),
      _NavItem(
        label: 'Subscriptions',
        icon: Icons.workspace_premium_rounded,
        route: '/dashboard/vendor-subscriptions',
        requiredPermission: 'vendor.view',
      ),
      _NavItem(
        label: 'Vendor Tiers',
        icon: Icons.layers_rounded,
        route: '/dashboard/vendor-tiers',
        requiredPermission: 'vendor.view',
      ),
    ],
  ),
  _NavGroup(
    label: 'Customers',
    icon: Icons.people_rounded,
    children: [
      _NavItem(
        label: 'Customers',
        icon: Icons.people_rounded,
        route: '/dashboard/customers',
        requiredPermission: 'customer.view',
      ),
      _NavItem(
        label: 'Abandoned Carts',
        icon: Icons.shopping_cart_outlined,
        route: '/dashboard/abandoned-carts',
        requiredPermission: 'customer.view',
      ),
    ],
  ),
  _NavGroup(
    label: 'Loyalty & Coupons',
    icon: Icons.stars_rounded,
    children: [
      _NavItem(
        label: 'Loyalty',
        icon: Icons.stars_rounded,
        route: '/dashboard/loyalty',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'Coupons',
        icon: Icons.local_offer_rounded,
        route: '/dashboard/coupons',
        requiredPermission: 'coupon.view',
      ),
    ],
  ),
  _NavGroup(
    label: 'Scheduling',
    icon: Icons.schedule_rounded,
    children: [
      _NavItem(
        label: 'Global Schedule',
        icon: Icons.schedule_rounded,
        route: '/dashboard/global-scheduling',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'Availability Blocks',
        icon: Icons.event_busy_rounded,
        route: '/dashboard/availability-blocks',
        requiredPermission: 'settings.manage',
      ),
    ],
  ),
  _NavGroup(
    label: 'Analytics',
    icon: Icons.insights_rounded,
    children: [
      _NavItem(
        label: 'Dispatch Analytics',
        icon: Icons.insights_rounded,
        route: '/dashboard/dispatch-analytics',
        requiredPermission: 'booking.view',
      ),
      _NavItem(
        label: 'GPS Audit',
        icon: Icons.my_location_rounded,
        route: '/dashboard/gps-audit',
        requiredPermission: 'booking.view',
      ),
      _NavItem(
        label: 'GPS Analytics',
        icon: Icons.analytics_rounded,
        route: '/dashboard/gps-analytics',
        requiredPermission: 'booking.view',
      ),
      _NavItem(
        label: 'Warranty Analytics',
        icon: Icons.analytics_rounded,
        route: '/dashboard/warranty-analytics',
        requiredPermission: 'booking.view',
      ),
    ],
  ),
  _NavGroup(
    label: 'Configuration',
    icon: Icons.settings_rounded,
    children: [
      _NavItem(
        label: 'Tax Settings',
        icon: Icons.receipt_long_rounded,
        route: '/dashboard/tax-settings',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'Platform Commission',
        icon: Icons.percent_rounded,
        route: '/dashboard/commission',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'Surge Fee',
        icon: Icons.bolt_rounded,
        route: '/dashboard/surge-fees',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'Online Payments',
        icon: Icons.payment_rounded,
        route: '/dashboard/payment-config',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'SEO',
        icon: Icons.travel_explore_rounded,
        route: '/dashboard/seo',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'Landing Page',
        icon: Icons.web_rounded,
        route: '/dashboard/landing-page',
        requiredPermission: 'settings.manage',
      ),
      _NavItem(
        label: 'Settings',
        icon: Icons.settings_rounded,
        route: '/dashboard/settings',
        requiredPermission: 'settings.manage',
      ),
    ],
  ),
  _NavGroup(
    label: 'Support',
    icon: Icons.support_agent_rounded,
    children: [
      _NavItem(
        label: 'Support Chat',
        icon: Icons.support_agent_rounded,
        route: '/dashboard/support',
        requiredPermission: 'booking.view',
      ),
      _NavItem(
        label: 'Call Sessions',
        icon: Icons.phone_in_talk_rounded,
        route: '/dashboard/call-sessions',
        requiredPermission: 'booking.view',
      ),
    ],
  ),
];

// ── SidebarNav ────────────────────────────────────────────────────────────────

class SidebarNav extends ConsumerStatefulWidget {
  const SidebarNav({super.key});

  @override
  ConsumerState<SidebarNav> createState() => _SidebarNavState();
}

class _SidebarNavState extends ConsumerState<SidebarNav> {
  String? _expandedGroup;
  final Set<String> _userClosedGroups = {};

  bool _isActive(String location, String route) {
    if (route == '/dashboard') return location == '/dashboard';
    return location.startsWith(route);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final adminUser = ref.watch(currentAdminUserProvider);

    // Which groups contain the active route.
    final activeGroupLabels = <String>{};
    for (final group in _kNavGroups) {
      if (group.children.any((item) => _isActive(location, item.route))) {
        activeGroupLabels.add(group.label);
      }
    }

    // Accordion: at most ONE group is ever open.
    // If the user manually expanded a group, only that group shows.
    // Otherwise the active route's group auto-expands (unless manually closed).
    final effectiveExpanded = _expandedGroup != null
        ? {_expandedGroup!}
        : activeGroupLabels.difference(_userClosedGroups);

    return Container(
      color: AppColors.sidebarBg,
      child: Column(
        children: [
          _SidebarBrand(),
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
                _NavTile(
                  item: _kDashboard,
                  isActive: location == '/dashboard',
                ),
                for (final group in _kNavGroups)
                  _buildGroup(group, location, effectiveExpanded, activeGroupLabels),
              ],
            ),
          ),
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

  Widget _buildGroup(
    _NavGroup group,
    String location,
    Set<String> effectiveExpanded,
    Set<String> activeGroupLabels,
  ) {
    final visibleChildren = group.children.where((item) {
      if (item.requiredPermission == null) return true;
      return ref.watch(hasPermissionProvider(item.requiredPermission!));
    }).toList();

    if (visibleChildren.isEmpty) return const SizedBox.shrink();

    final isExpanded = effectiveExpanded.contains(group.label);
    final isGroupActive = activeGroupLabels.contains(group.label);

    return _NavGroupTile(
      label: group.label,
      icon: group.icon,
      isExpanded: isExpanded,
      isActive: isGroupActive,
      onToggle: () {
        setState(() {
          if (isExpanded) {
            if (_expandedGroup == group.label) _expandedGroup = null;
            _userClosedGroups.add(group.label);
          } else {
            _expandedGroup = group.label;
            _userClosedGroups.remove(group.label);
            // Close any auto-expanded active groups (accordion: only one open at a time).
            _userClosedGroups.addAll(activeGroupLabels);
          }
        });
      },
      children: [
        for (final item in visibleChildren)
          _NavTile(
            item: item,
            isActive: _isActive(location, item.route),
            isChild: true,
          ),
      ],
    );
  }
}

// ── _NavGroupTile ─────────────────────────────────────────────────────────────

class _NavGroupTile extends StatefulWidget {
  const _NavGroupTile({
    required this.label,
    required this.icon,
    required this.isExpanded,
    required this.isActive,
    required this.onToggle,
    required this.children,
  });

  final String label;
  final IconData icon;
  final bool isExpanded;
  final bool isActive;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  State<_NavGroupTile> createState() => _NavGroupTileState();
}

class _NavGroupTileState extends State<_NavGroupTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: widget.isActive
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : _hovered
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: widget.isActive
                    ? Border.all(color: AppColors.accent.withValues(alpha: 0.4))
                    : Border.all(color: Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.icon,
                    size: 18,
                    color: widget.isActive
                        ? AppColors.sidebarActiveText
                        : AppColors.sidebarText,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.isActive
                            ? AppColors.sidebarActiveText
                            : AppColors.sidebarText,
                        fontSize: 13.5,
                        fontWeight: widget.isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: widget.isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: widget.isActive
                          ? AppColors.sidebarActiveText
                          : AppColors.sidebarText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: widget.isExpanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.children,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── _NavTile ──────────────────────────────────────────────────────────────────

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.isActive,
    this.isChild = false,
  });
  final _NavItem item;
  final bool isActive;
  final bool isChild;

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
          margin: EdgeInsets.only(
            left: widget.isChild ? 26 : 12,
            right: 12,
            top: 1,
            bottom: 1,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: widget.isChild ? 8 : 10,
          ),
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
              if (widget.isChild) ...[
                Container(
                  width: 2,
                  height: 14,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.accent
                        : AppColors.sidebarText.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 10),
              ] else ...[
                Icon(
                  widget.item.icon,
                  size: 18,
                  color: active
                      ? AppColors.sidebarActiveText
                      : AppColors.sidebarText,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  widget.item.label,
                  style: TextStyle(
                    color: active
                        ? AppColors.sidebarActiveText
                        : AppColors.sidebarText,
                    fontSize: widget.isChild ? 13 : 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
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

// ── _SidebarBrand ─────────────────────────────────────────────────────────────

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
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(3),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
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

// ── _SidebarFooter ────────────────────────────────────────────────────────────

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

// ── _LogoutButton ─────────────────────────────────────────────────────────────

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
