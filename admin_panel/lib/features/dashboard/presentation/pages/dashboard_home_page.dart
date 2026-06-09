import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../application/providers/dashboard_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';

class DashboardHomePage extends ConsumerWidget {
  const DashboardHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminUser = ref.watch(currentAdminUserProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Welcome banner ─────────────────────────────────────────────────
          _WelcomeBanner(displayName: adminUser?.displayName ?? 'Admin'),
          const SizedBox(height: 28),

          // ── Stats row ──────────────────────────────────────────────────────
          const _StatsGrid(),
          const SizedBox(height: 28),

          // ── Quick actions ──────────────────────────────────────────────────
          const _QuickActions(),
        ],
      ),
    );
  }
}

class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.displayName});
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $displayName 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Welcome to DODO BOOKER Admin Panel. Manage your platform from here.',
                  style: TextStyle(
                    color: Color(0xFFB0C4DE),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(
            Icons.rocket_launch_rounded,
            size: 56,
            color: Color(0xFF4A90D9),
          ),
        ],
      ),
    );
  }
}

// ── Stats grid ─────────────────────────────────────────────────────────────────

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final vendorsAsync = ref.watch(vendorsNotifierProvider);
    final isLoading = vendorsAsync.isLoading;

    final items = [
      _StatData(
        label: 'Total Vendors',
        value: isLoading ? '…' : '${stats.totalVendors}',
        icon: Icons.store_rounded,
        color: const Color(0xFF4A90D9),
      ),
      _StatData(
        label: 'Active Vendors',
        value: isLoading ? '…' : '${stats.activeVendors}',
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF38A169),
      ),
      _StatData(
        label: 'Total Bookings',
        value: '—',
        icon: Icons.book_online_rounded,
        color: const Color(0xFFDD6B20),
      ),
      _StatData(
        label: 'Customers',
        value: '—',
        icon: Icons.people_rounded,
        color: const Color(0xFF805AD5),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 600
                ? 2
                : 1;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.2,
          children: items.map((s) => _StatCard(data: s)).toList(),
        );
      },
    );
  }
}

class _StatData {
  const _StatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: data.color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
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

// ── Quick actions ──────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: const Center(
            child: Column(
              children: [
                Icon(
                  Icons.construction_rounded,
                  size: 40,
                  color: AppColors.textSecondary,
                ),
                SizedBox(height: 12),
                Text(
                  'Business modules are being built.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Use the sidebar to navigate between sections.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
