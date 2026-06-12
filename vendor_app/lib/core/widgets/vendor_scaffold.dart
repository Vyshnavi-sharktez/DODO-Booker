import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../routes/route_names.dart';

/// Shared scaffold for all authenticated pages.
///
/// Wraps [child] with a top [AppBar] and a persistent [NavigationBar].
/// The current tab is derived from the live GoRouter location so no external
/// state is needed — each page simply passes its own title and body.
class VendorScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    // clamp so -1 (no match) falls back to Dashboard (index 0)
    final currentIndex =
        _tabs.indexWhere((t) => t.path == location).clamp(0, _tabs.length - 1);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: actions,
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
    );
  }
}

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
