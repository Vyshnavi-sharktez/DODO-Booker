import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../../../features/notifications/application/providers/notifications_providers.dart';

class TopHeader extends ConsumerWidget {
  const TopHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminUser = ref.watch(currentAdminUserProvider);
    final title = _resolveTitle(GoRouterState.of(context).matchedLocation);
    final unreadCount = ref.watch(unreadCountProvider);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Page title
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),

          const Spacer(),

          // Notification bell — navigates to /dashboard/notifications
          _HeaderIconButton(
            icon: Icons.notifications_outlined,
            onTap: () => context.go('/dashboard/notifications'),
            badgeCount: unreadCount,
          ),
          const SizedBox(width: 8),

          // User avatar chip
          if (adminUser != null)
            _UserChip(
              displayName: adminUser.displayName,
              role: adminUser.primaryRole,
              onLogout: () =>
                  ref.read(authNotifierProvider.notifier).logout(),
            ),
        ],
      ),
    );
  }

  String _resolveTitle(String location) {
    const titles = {
      '/dashboard': 'Dashboard',
      '/dashboard/rbac': 'RBAC & User Management',
      '/dashboard/categories': 'Categories',
      '/dashboard/sub-categories': 'Sub Categories',
      '/dashboard/services': 'Services',
      '/dashboard/vendors': 'Vendors',
      '/dashboard/bookings': 'Bookings',
      '/dashboard/customers': 'Customers',
      '/dashboard/coupons': 'Coupons & Promotions',
      '/dashboard/notifications': 'Notifications',
      '/dashboard/settings': 'Settings',
    };
    return titles[location] ?? 'Admin Panel';
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _hovered
                    ? AppColors.border
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.icon,
                size: 22,
                color: AppColors.textSecondary,
              ),
            ),
            if (widget.badgeCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${widget.badgeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserChip extends StatefulWidget {
  const _UserChip({
    required this.displayName,
    required this.role,
    required this.onLogout,
  });
  final String displayName;
  final String role;
  final VoidCallback onLogout;

  @override
  State<_UserChip> createState() => _UserChipState();
}

class _UserChipState extends State<_UserChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'logout') widget.onLogout();
        },
        offset: const Offset(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        itemBuilder: (context) => [
          PopupMenuItem(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                Text(
                  widget.role,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'logout',
            child: Row(
              children: [
                Icon(Icons.logout_rounded, size: 16, color: AppColors.error),
                SizedBox(width: 8),
                Text(
                  'Sign Out',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.border : AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.primary.withValues(alpha:0.12),
                child: Text(
                  widget.displayName.isNotEmpty
                      ? widget.displayName[0].toUpperCase()
                      : 'A',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.displayName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    widget.role,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
