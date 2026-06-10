import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/top_header.dart';

class DashboardShell extends StatelessWidget {
  const DashboardShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > AppBreakpoints.tablet;
        if (isDesktop) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Row(
              children: [
                // Persistent sidebar on desktop
                const SizedBox(width: 250, child: SidebarNav()),
                Expanded(
                  child: Column(
                    children: [
                      const TopHeader(),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Tablet / Mobile — collapsible drawer
        return Scaffold(
          backgroundColor: AppColors.background,
          drawer: const Drawer(
            width: 250,
            child: SidebarNav(),
          ),
          body: Column(
            children: [
              const TopHeader(showHamburger: true),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}
