import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';

/// Horizontal section-navigation strip shared by all InstaHelp pages.
class InstaHelpNav extends StatelessWidget {
  const InstaHelpNav({super.key});

  static const _tabs = [
    (label: 'Overview', route: '/dashboard/instahelp', icon: Icons.dashboard_rounded),
    (label: "What's Included", route: '/dashboard/instahelp/included', icon: Icons.check_circle_outline_rounded),
    (label: 'Excluded Activities', route: '/dashboard/instahelp/excluded', icon: Icons.do_not_disturb_alt_rounded),
    (label: 'Duration & Pricing', route: '/dashboard/instahelp/pricing', icon: Icons.timer_rounded),
    (label: 'Vendors', route: '/dashboard/instahelp/vendors', icon: Icons.store_rounded),
    (label: 'Serving Areas', route: '/dashboard/instahelp/serving-areas', icon: Icons.map_rounded),
    (label: 'Bookings', route: '/dashboard/instahelp/bookings', icon: Icons.book_online_rounded),
    (label: 'Settings', route: '/dashboard/instahelp/settings', icon: Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _tabs.map((tab) {
            final isActive = tab.route == '/dashboard/instahelp'
                ? location == '/dashboard/instahelp'
                : location.startsWith(tab.route);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _NavTab(
                label: tab.label,
                icon: tab.icon,
                route: tab.route,
                isActive: isActive,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  const _NavTab({
    required this.label,
    required this.icon,
    required this.route,
    required this.isActive,
  });
  final String label;
  final IconData icon;
  final String route;
  final bool isActive;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(widget.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.primary
                : _hovered
                    ? AppColors.background
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 15,
                color: widget.isActive ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      widget.isActive ? FontWeight.w600 : FontWeight.w400,
                  color: widget.isActive ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
