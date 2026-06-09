import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../application/providers/dashboard_providers.dart';
import '../../../categories/application/providers/categories_providers.dart';
import '../../../sub_categories/application/providers/sub_categories_providers.dart';
import '../../../services/application/providers/services_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../coupons/application/providers/coupons_providers.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

// ── Page ──────────────────────────────────────────────────────────────────────

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
          _WelcomeBanner(displayName: adminUser?.displayName ?? 'Admin'),
          const SizedBox(height: 28),
          const _StatsSection(),
          const SizedBox(height: 28),
          const _AnalyticsRow(),
          const SizedBox(height: 28),
          const _RecentActivitySection(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Welcome banner ─────────────────────────────────────────────────────────────

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
                  style: TextStyle(color: Color(0xFFB0C4DE), fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.rocket_launch_rounded,
              size: 56, color: Color(0xFF4A90D9)),
        ],
      ),
    );
  }
}

// ── Stats section — 6 cards ────────────────────────────────────────────────────

class _StatsSection extends ConsumerWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);

    final loadingCat =
        ref.watch(categoriesNotifierProvider).isLoading;
    final loadingSub =
        ref.watch(subCategoriesNotifierProvider).isLoading;
    final loadingSvc =
        ref.watch(servicesNotifierProvider).isLoading;
    final loadingVnd =
        ref.watch(vendorsNotifierProvider).isLoading;
    final loadingBkg =
        ref.watch(bookingsNotifierProvider).isLoading;
    final loadingCpn =
        ref.watch(couponsNotifierProvider).isLoading;

    final cards = [
      _StatCardData(
        label: 'Categories',
        value: loadingCat ? null : stats.totalCategories,
        icon: Icons.category_rounded,
        color: const Color(0xFF4A90D9),
      ),
      _StatCardData(
        label: 'Sub Categories',
        value: loadingSub ? null : stats.totalSubCategories,
        icon: Icons.list_alt_rounded,
        color: const Color(0xFF3182CE),
      ),
      _StatCardData(
        label: 'Services',
        value: loadingSvc ? null : stats.totalServices,
        icon: Icons.home_repair_service_rounded,
        color: const Color(0xFF805AD5),
      ),
      _StatCardData(
        label: 'Vendors',
        value: loadingVnd ? null : stats.totalVendors,
        icon: Icons.store_rounded,
        color: const Color(0xFF38A169),
      ),
      _StatCardData(
        label: 'Bookings',
        value: loadingBkg ? null : stats.totalBookings,
        icon: Icons.book_online_rounded,
        color: const Color(0xFFDD6B20),
      ),
      _StatCardData(
        label: 'Coupons',
        value: loadingCpn ? null : stats.totalCoupons,
        icon: Icons.local_offer_rounded,
        color: const Color(0xFFE53E3E),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 1100
            ? 6
            : constraints.maxWidth > 700
                ? 3
                : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.0,
          children: cards.map(_StatCard.new).toList(),
        );
      },
    );
  }
}

class _StatCardData {
  final String label;
  final int? value; // null = loading
  final IconData icon;
  final Color color;
  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.data);
  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                data.value == null
                    ? SizedBox(
                        width: 32,
                        height: 20,
                        child: LinearProgressIndicator(
                          backgroundColor:
                              data.color.withValues(alpha: 0.1),
                          valueColor:
                              AlwaysStoppedAnimation(data.color),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    : Text(
                        '${data.value}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                const SizedBox(height: 2),
                Text(
                  data.label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Analytics row — Booking breakdown + Vendor summary ────────────────────────

class _AnalyticsRow extends ConsumerWidget {
  const _AnalyticsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 800;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(flex: 3, child: _BookingAnalyticsCard()),
              SizedBox(width: 16),
              Expanded(flex: 2, child: _VendorSummaryCard()),
            ],
          );
        }
        return const Column(
          children: [
            _BookingAnalyticsCard(),
            SizedBox(height: 16),
            _VendorSummaryCard(),
          ],
        );
      },
    );
  }
}

// ── Booking analytics card ─────────────────────────────────────────────────────

const _bookingStatusRows = [
  ('pending', 'Pending', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  ('assigned', 'Assigned', Color(0xFF3182CE), Color(0xFFEBF8FF)),
  ('in_progress', 'In Progress', Color(0xFF805AD5), Color(0xFFFAF5FF)),
  ('completed', 'Completed', Color(0xFF38A169), Color(0xFFF0FFF4)),
  ('cancelled', 'Cancelled', Color(0xFFE53E3E), Color(0xFFFFF5F5)),
];

class _BookingAnalyticsCard extends ConsumerWidget {
  const _BookingAnalyticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingsNotifierProvider);
    final stats = ref.watch(dashboardStatsProvider);

    final counts = {
      'pending': stats.bookingsPending,
      'assigned': stats.bookingsAssigned,
      'in_progress': stats.bookingsInProgress,
      'completed': stats.bookingsCompleted,
      'cancelled': stats.bookingsCancelled,
    };

    final total = stats.totalBookings;

    return _SectionCard(
      title: 'Booking Analytics',
      icon: Icons.bar_chart_rounded,
      child: bookingsAsync.isLoading
          ? const _LoadingPlaceholder(height: 160)
          : bookingsAsync.hasError
              ? _ErrorPlaceholder(
                  message: bookingsAsync.error.toString())
              : total == 0
                  ? const _EmptyPlaceholder(message: 'No bookings yet')
                  : Column(
                      children: [
                        ..._bookingStatusRows.map((row) {
                          final count = counts[row.$1] ?? 0;
                          final fraction =
                              total > 0 ? count / total : 0.0;
                          return _BookingStatusRow(
                            label: row.$2,
                            count: count,
                            fraction: fraction,
                            color: row.$3,
                            bg: row.$4,
                          );
                        }),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Total: $total',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
    );
  }
}

class _BookingStatusRow extends StatelessWidget {
  final String label;
  final int count;
  final double fraction;
  final Color color;
  final Color bg;

  const _BookingStatusRow({
    required this.label,
    required this.count,
    required this.fraction,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 32,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vendor summary card ────────────────────────────────────────────────────────

class _VendorSummaryCard extends ConsumerWidget {
  const _VendorSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vendorsNotifierProvider);
    final stats = ref.watch(dashboardStatsProvider);

    return _SectionCard(
      title: 'Vendor Summary',
      icon: Icons.store_rounded,
      child: vendorsAsync.isLoading
          ? const _LoadingPlaceholder(height: 120)
          : vendorsAsync.hasError
              ? _ErrorPlaceholder(message: vendorsAsync.error.toString())
              : stats.totalVendors == 0
                  ? const _EmptyPlaceholder(message: 'No vendors yet')
                  : Column(
                      children: [
                        _SummaryRow(
                          label: 'Total Vendors',
                          value: '${stats.totalVendors}',
                          color: const Color(0xFF38A169),
                          icon: Icons.store_rounded,
                        ),
                        const SizedBox(height: 10),
                        _SummaryRow(
                          label: 'Active',
                          value: '${stats.activeVendors}',
                          color: const Color(0xFF38A169),
                          icon: Icons.check_circle_outline_rounded,
                        ),
                        const SizedBox(height: 10),
                        _SummaryRow(
                          label: 'Inactive',
                          value:
                              '${stats.totalVendors - stats.activeVendors}',
                          color: const Color(0xFF718096),
                          icon: Icons.cancel_outlined,
                        ),
                        const Divider(height: 20),
                        _SummaryRow(
                          label: 'Active Coupons',
                          value: '${stats.activeCoupons}',
                          color: const Color(0xFFDD6B20),
                          icon: Icons.local_offer_rounded,
                        ),
                      ],
                    ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Recent activity section ────────────────────────────────────────────────────

class _RecentActivitySection extends ConsumerWidget {
  const _RecentActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 900;
            if (wide) {
              return const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _RecentVendors()),
                  SizedBox(width: 16),
                  Expanded(child: _RecentBookings()),
                  SizedBox(width: 16),
                  Expanded(child: _RecentCoupons()),
                ],
              );
            }
            return const Column(
              children: [
                _RecentVendors(),
                SizedBox(height: 16),
                _RecentBookings(),
                SizedBox(height: 16),
                _RecentCoupons(),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ── Recent vendors ─────────────────────────────────────────────────────────────

class _RecentVendors extends ConsumerWidget {
  const _RecentVendors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vendorsNotifierProvider);

    return _SectionCard(
      title: 'Recent Vendors',
      icon: Icons.store_rounded,
      child: vendorsAsync.when(
        loading: () => const _LoadingPlaceholder(height: 200),
        error: (e, _) => _ErrorPlaceholder(message: e.toString()),
        data: (vendors) {
          if (vendors.isEmpty) {
            return const _EmptyPlaceholder(message: 'No vendors yet');
          }
          final recent = vendors.take(5).toList();
          return Column(
            children: recent.map((v) {
              return _ActivityItem(
                icon: Icons.store_rounded,
                iconColor: const Color(0xFF38A169),
                title: v.businessName,
                subtitle: v.city.isNotEmpty ? v.city : 'No city',
                trailing: v.isActive ? 'Active' : 'Inactive',
                trailingColor: v.isActive
                    ? const Color(0xFF38A169)
                    : const Color(0xFF718096),
                date: v.createdAt,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ── Recent bookings ────────────────────────────────────────────────────────────

const _bookingStatusColors = <String, Color>{
  'pending': Color(0xFFDD6B20),
  'assigned': Color(0xFF3182CE),
  'in_progress': Color(0xFF805AD5),
  'completed': Color(0xFF38A169),
  'cancelled': Color(0xFFE53E3E),
};

const _bookingStatusLabels = <String, String>{
  'pending': 'Pending',
  'assigned': 'Assigned',
  'in_progress': 'In Progress',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
};

class _RecentBookings extends ConsumerWidget {
  const _RecentBookings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingsNotifierProvider);

    return _SectionCard(
      title: 'Recent Bookings',
      icon: Icons.book_online_rounded,
      child: bookingsAsync.when(
        loading: () => const _LoadingPlaceholder(height: 200),
        error: (e, _) => _ErrorPlaceholder(message: e.toString()),
        data: (bookings) {
          if (bookings.isEmpty) {
            return const _EmptyPlaceholder(message: 'No bookings yet');
          }
          final recent = bookings.take(5).toList();
          return Column(
            children: recent.map((b) {
              final statusLabel =
                  _bookingStatusLabels[b.status] ?? b.status;
              final statusColor =
                  _bookingStatusColors[b.status] ?? AppColors.textSecondary;
              return _ActivityItem(
                icon: Icons.receipt_long_rounded,
                iconColor: const Color(0xFFDD6B20),
                title: '#${b.bookingNumber}',
                subtitle: b.serviceDate != null
                    ? _dateFmt.format(b.serviceDate!)
                    : 'No date',
                trailing: statusLabel,
                trailingColor: statusColor,
                date: b.createdAt,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ── Recent coupons ─────────────────────────────────────────────────────────────

class _RecentCoupons extends ConsumerWidget {
  const _RecentCoupons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couponsAsync = ref.watch(couponsNotifierProvider);

    return _SectionCard(
      title: 'Recent Coupons',
      icon: Icons.local_offer_rounded,
      child: couponsAsync.when(
        loading: () => const _LoadingPlaceholder(height: 200),
        error: (e, _) => _ErrorPlaceholder(message: e.toString()),
        data: (coupons) {
          if (coupons.isEmpty) {
            return const _EmptyPlaceholder(message: 'No coupons yet');
          }
          final recent = coupons.take(5).toList();
          return Column(
            children: recent.map((c) {
              final valueStr = c.discountType == 'percentage'
                  ? '${c.discountValue.toStringAsFixed(c.discountValue % 1 == 0 ? 0 : 1)}% off'
                  : '${_currency.format(c.discountValue)} off';
              final statusLabel = c.isExpired
                  ? 'Expired'
                  : c.isActive
                      ? 'Active'
                      : 'Inactive';
              final statusColor = c.isExpired
                  ? const Color(0xFFE53E3E)
                  : c.isActive
                      ? const Color(0xFF38A169)
                      : const Color(0xFF718096);
              return _ActivityItem(
                icon: Icons.local_offer_rounded,
                iconColor: const Color(0xFFE53E3E),
                title: c.code,
                subtitle: valueStr,
                trailing: statusLabel,
                trailingColor: statusColor,
                date: c.createdAt,
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String trailing;
  final Color trailingColor;
  final DateTime? date;

  const _ActivityItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.trailingColor,
    this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: trailingColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trailing,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: trailingColor,
                  ),
                ),
              ),
              if (date != null) ...[
                const SizedBox(height: 2),
                Text(
                  _dateFmt.format(date!),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  final double height;
  const _LoadingPlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  final String message;
  const _ErrorPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.error,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  final String message;
  const _EmptyPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
