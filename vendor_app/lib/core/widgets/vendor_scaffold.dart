import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../routes/route_names.dart';
import '../../features/location/application/location_tracking_service.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';

/// Shared scaffold for all authenticated pages.
///
/// Wraps [child] with a top [AppBar] containing a persistent notification bell
/// and a [NavigationBar] at the bottom. The current tab is derived from the
/// live GoRouter location — no external state needed.
class VendorScaffold extends ConsumerWidget {
  const VendorScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  static const _tabs = [
    _NavTab(
      path: RoutePaths.dashboard,
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
    ),
    _NavTab(
      path: RoutePaths.bookings,
      label: 'Bookings',
      icon: Icons.book_online_outlined,
      selectedIcon: Icons.book_online_rounded,
    ),
    _NavTab(
      path: RoutePaths.services,
      label: 'Services',
      icon: Icons.home_repair_service_outlined,
      selectedIcon: Icons.home_repair_service_rounded,
    ),
    _NavTab(
      path: RoutePaths.profile,
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
    _NavTab(
      path: RoutePaths.settings,
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(activeBookingTrackerObserver, (_, __) {});
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex =
        _tabs.indexWhere((t) => t.path == location).clamp(0, _tabs.length - 1);
    final unreadCount = ref.watch(vendorUnreadCountProvider);

    // True only when this VendorScaffold is rendering one of the 5 bottom-nav
    // tab pages (the pages navigated to via context.go). Pushed child pages
    // that happen to use VendorScaffold (e.g. notifications) have a location
    // that is NOT in _tabs, so they keep canPop:true and get the auto-inserted
    // AppBar ← button from Flutter for free.
    final isTabPage = _tabs.any((t) => t.path == location);
    final isRootTab = location == RoutePaths.dashboard;

    return PopScope(
      // Non-root tab pages intercept Back and go to Dashboard.
      // Root (Dashboard) and pushed child pages allow the default behavior.
      canPop: !isTabPage || isRootTab,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(RoutePaths.dashboard);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            ...?actions,
            _NotificationBell(
              unreadCount: unreadCount,
              onTap: () => context.push(RoutePaths.notifications),
            ),
          ],
        ),
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (i) {
            if (_tabs[i].path != location) context.go(_tabs[i].path);
          },
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.primaryLight,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: _tabs
              .map(
                (t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

// ── Notification bell with badge ──────────────────────────────────────────────

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({
    required this.unreadCount,
    required this.onTap,
  });

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'Notifications',
          onPressed: onTap,
        ),
        if (unreadCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.6,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Nav tab descriptor ────────────────────────────────────────────────────────

class _NavTab {
  const _NavTab({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
