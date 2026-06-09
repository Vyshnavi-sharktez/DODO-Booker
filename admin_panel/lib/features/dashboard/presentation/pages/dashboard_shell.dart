import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/top_header.dart';

class DashboardShell extends StatelessWidget {
  const DashboardShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // ── Fixed sidebar ──────────────────────────────────────────────────
          const SidebarNav(),

          // ── Main content area ──────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                const TopHeader(),
                Expanded(
                  child: child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
