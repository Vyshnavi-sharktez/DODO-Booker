import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../../../customers/application/providers/customers_providers.dart';
import '../../../dodo_teams/application/providers/dodo_teams_providers.dart';
import '../../../vendor_settlement/application/providers/vendor_settlement_providers.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _dateFmtShort = DateFormat('dd MMM');
final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
final _currencyK =
    NumberFormat.compactCurrency(symbol: '₹', decimalDigits: 1);

// ── Page ──────────────────────────────────────────────────────────────────────

class DashboardHomePage extends ConsumerWidget {
  const DashboardHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminUser = ref.watch(currentAdminUserProvider);

    // Trigger loading of all data sources used on this page
    ref.watch(bookingsNotifierProvider);
    ref.watch(vendorsNotifierProvider);
    ref.watch(customersNotifierProvider);
    ref.watch(dodoTeamsNotifierProvider);
    ref.watch(categoriesNotifierProvider);
    ref.watch(subCategoriesNotifierProvider);
    ref.watch(servicesNotifierProvider);
    ref.watch(couponsNotifierProvider);
    ref.watch(vendorSettlementNotifierProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeBanner(displayName: adminUser?.displayName ?? 'Admin'),
          const SizedBox(height: 24),
          const _OverviewSection(),
          const SizedBox(height: 24),
          const _RevenueAndActionsRow(),
          const SizedBox(height: 24),
          const _ChartsRow(),
          const SizedBox(height: 24),
          const _ChartsRow2(),
          const SizedBox(height: 24),
          const _BottomInfoRow(),
          const SizedBox(height: 24),
          const _QuickActionsRow(),
          const SizedBox(height: 24),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 480;
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting, $displayName 👋',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: constraints.maxWidth < 400 ? 17 : 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'DODO BOOKER Admin Panel — ${_dateFmt.format(DateTime.now())}',
                      style: const TextStyle(
                          color: Color(0xFFB0C4DE), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const _RefreshButton(),
              if (wide) ...[
                const SizedBox(width: 12),
                const Icon(Icons.rocket_launch_rounded,
                    size: 48, color: Color(0xFF4A90D9)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RefreshButton extends ConsumerStatefulWidget {
  const _RefreshButton();

  @override
  ConsumerState<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends ConsumerState<_RefreshButton> {
  bool _loading = false;

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    await Future.wait([
      ref.read(bookingsNotifierProvider.notifier).refresh(),
      ref.read(vendorsNotifierProvider.notifier).refresh(),
      ref.read(customersNotifierProvider.notifier).refresh(),
      ref.read(dodoTeamsNotifierProvider.notifier).refresh(),
      ref.read(categoriesNotifierProvider.notifier).refresh(),
      ref.read(subCategoriesNotifierProvider.notifier).refresh(),
      ref.read(servicesNotifierProvider.notifier).refresh(),
      ref.read(couponsNotifierProvider.notifier).refresh(),
      ref.read(vendorSettlementNotifierProvider.notifier).refresh(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Refresh dashboard',
      child: InkWell(
        onTap: _refresh,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.refresh_rounded,
                  size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

// ── Overview cards — 8 key metrics ────────────────────────────────────────────

class _OverviewSection extends ConsumerWidget {
  const _OverviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final sysHealth = ref.watch(dashboardSystemHealthProvider);
    final bookingsLoading = ref.watch(bookingsNotifierProvider).isLoading;
    final vendorsLoading = ref.watch(vendorsNotifierProvider).isLoading;
    final customersLoading = ref.watch(customersNotifierProvider).isLoading;
    final teamsLoading = ref.watch(dodoTeamsNotifierProvider).isLoading;
    final servicesLoading = ref.watch(servicesNotifierProvider).isLoading;
    final teams = ref.watch(dodoTeamsNotifierProvider).valueOrNull ?? [];
    final customers = ref.watch(customersNotifierProvider).valueOrNull ?? [];

    final cards = [
      _OverviewCardData(
        label: 'Total Bookings',
        value: bookingsLoading ? null : stats.totalBookings,
        icon: Icons.book_online_rounded,
        color: const Color(0xFFDD6B20),
      ),
      _OverviewCardData(
        label: 'Pending',
        value: bookingsLoading ? null : stats.bookingsPending,
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFFC05621),
      ),
      _OverviewCardData(
        label: 'In Progress',
        value: bookingsLoading ? null : stats.bookingsInProgress,
        icon: Icons.pending_actions_rounded,
        color: const Color(0xFF805AD5),
      ),
      _OverviewCardData(
        label: 'Completed',
        value: bookingsLoading ? null : stats.bookingsCompleted,
        icon: Icons.check_circle_outline_rounded,
        color: const Color(0xFF38A169),
      ),
      _OverviewCardData(
        label: 'Active Vendors',
        value: vendorsLoading ? null : stats.activeVendors,
        icon: Icons.store_rounded,
        color: const Color(0xFF3182CE),
      ),
      _OverviewCardData(
        label: 'DODO Teams',
        value: teamsLoading ? null : teams.length,
        icon: Icons.groups_rounded,
        color: const Color(0xFF319795),
      ),
      _OverviewCardData(
        label: 'Customers',
        value: customersLoading ? null : customers.length,
        icon: Icons.people_alt_rounded,
        color: const Color(0xFF744210),
      ),
      _OverviewCardData(
        label: 'Active Services',
        value: servicesLoading ? null : sysHealth.activeServices,
        icon: Icons.home_repair_service_rounded,
        color: const Color(0xFFB7791F),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > AppBreakpoints.tablet ? 4 : 2;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: cols == 2 ? 2.2 : 2.8,
          children: cards.map(_OverviewCard.new).toList(),
        );
      },
    );
  }
}

class _OverviewCardData {
  final String label;
  final int? value;
  final IconData icon;
  final Color color;
  const _OverviewCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard(this.data);
  final _OverviewCardData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(data.icon, color: data.color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                data.value == null
                    ? SizedBox(
                        width: 28,
                        height: 16,
                        child: LinearProgressIndicator(
                          backgroundColor:
                              data.color.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(data.color),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )
                    : Text(
                        '${data.value}',
                        style: const TextStyle(
                          fontSize: 20,
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

// ── Revenue + Pending Actions ─────────────────────────────────────────────────

class _RevenueAndActionsRow extends ConsumerWidget {
  const _RevenueAndActionsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenue = ref.watch(dashboardRevenueProvider);
    final actions = ref.watch(dashboardPendingActionsProvider);
    final bookingsLoading = ref.watch(bookingsNotifierProvider).isLoading;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > AppBreakpoints.mobile;
        final revenueCards = Row(
          children: [
            Expanded(
              child: _RevenueCard(
                label: "Today's Revenue",
                amount: revenue.today,
                icon: Icons.today_rounded,
                color: const Color(0xFF38A169),
                loading: bookingsLoading,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RevenueCard(
                label: 'This Week',
                amount: revenue.thisWeek,
                icon: Icons.date_range_rounded,
                color: const Color(0xFF3182CE),
                loading: bookingsLoading,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RevenueCard(
                label: 'This Month',
                amount: revenue.thisMonth,
                icon: Icons.calendar_month_rounded,
                color: const Color(0xFF805AD5),
                loading: bookingsLoading,
              ),
            ),
          ],
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: revenueCards),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _PendingActionsCard(actions: actions),
              ),
            ],
          );
        }
        return Column(
          children: [
            revenueCards,
            const SizedBox(height: 12),
            _PendingActionsCard(actions: actions),
          ],
        );
      },
    );
  }
}

class _RevenueCard extends StatelessWidget {
  final String label;
  final double amount;
  final IconData icon;
  final Color color;
  final bool loading;

  const _RevenueCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const Spacer(),
              Icon(Icons.trending_up_rounded,
                  size: 13, color: color.withValues(alpha: 0.6)),
            ],
          ),
          const SizedBox(height: 10),
          loading
              ? SizedBox(
                  width: 60,
                  height: 16,
                  child: LinearProgressIndicator(
                    backgroundColor: color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(color),
                    borderRadius: BorderRadius.circular(3),
                  ),
                )
              : Text(
                  _currencyK.format(amount),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingActionsCard extends StatelessWidget {
  final DashboardPendingActions actions;
  const _PendingActionsCard({required this.actions});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Pending Actions',
      icon: Icons.notifications_active_rounded,
      child: Column(
        children: [
          _ActionRow(
            label: 'Unassigned Bookings',
            count: actions.unassignedBookings,
            color: const Color(0xFFDD6B20),
            icon: Icons.assignment_late_rounded,
          ),
          const SizedBox(height: 8),
          _ActionRow(
            label: 'Pending Settlements',
            count: actions.pendingSettlements,
            color: const Color(0xFF805AD5),
            icon: Icons.payments_rounded,
          ),
          const SizedBox(height: 8),
          _ActionRow(
            label: 'Vendor Verifications',
            count: actions.pendingVendorVerifications,
            color: const Color(0xFF3182CE),
            icon: Icons.verified_user_rounded,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _ActionRow({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: count > 0
                ? color.withValues(alpha: 0.12)
                : AppColors.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: count > 0 ? color : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Charts row 1: Booking Status + Daily Revenue ──────────────────────────────

class _ChartsRow extends ConsumerWidget {
  const _ChartsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > AppBreakpoints.mobile;
        if (wide) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _BookingAnalyticsCard()),
              SizedBox(width: 16),
              Expanded(flex: 3, child: _RevenueChartCard()),
            ],
          );
        }
        return const Column(
          children: [
            _BookingAnalyticsCard(),
            SizedBox(height: 16),
            _RevenueChartCard(),
          ],
        );
      },
    );
  }
}

const _bookingStatusRows = [
  ('pending',     'Pending',     Color(0xFFDD6B20)),
  ('assigned',    'Assigned',    Color(0xFF3182CE)),
  ('accepted',    'Accepted',    Color(0xFF2C7A7B)),
  ('on_the_way',  'On The Way',  Color(0xFF4A6FA5)),
  ('arrived',     'Arrived',     Color(0xFF6B46C1)),
  ('in_progress', 'In Progress', Color(0xFF805AD5)),
  ('completed',   'Completed',   Color(0xFF38A169)),
  ('rejected',    'Rejected',    Color(0xFFC05621)),
  ('cancelled',   'Cancelled',   Color(0xFFE53E3E)),
];

class _BookingAnalyticsCard extends ConsumerWidget {
  const _BookingAnalyticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingsNotifierProvider);
    final stats = ref.watch(dashboardStatsProvider);

    final counts = {
      'pending':     stats.bookingsPending,
      'assigned':    stats.bookingsAssigned,
      'accepted':    stats.bookingsAccepted,
      'on_the_way':  stats.bookingsOnTheWay,
      'arrived':     stats.bookingsArrived,
      'in_progress': stats.bookingsInProgress,
      'completed':   stats.bookingsCompleted,
      'rejected':    stats.bookingsRejected,
      'cancelled':   stats.bookingsCancelled,
    };
    final total = stats.totalBookings;

    return _SectionCard(
      title: 'Booking Status',
      icon: Icons.bar_chart_rounded,
      child: bookingsAsync.isLoading
          ? const _LoadingPlaceholder(height: 150)
          : bookingsAsync.hasError
              ? _ErrorPlaceholder(message: bookingsAsync.error.toString())
              : total == 0
                  ? const _EmptyPlaceholder(message: 'No bookings yet')
                  : Column(
                      children: [
                        ..._bookingStatusRows.map((row) {
                          final count = counts[row.$1] ?? 0;
                          final fraction =
                              total > 0 ? count / total : 0.0;
                          return _HBarRow(
                            label: row.$2,
                            count: count,
                            fraction: fraction,
                            color: row.$3,
                          );
                        }),
                        const Divider(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Total: $total',
                              style: const TextStyle(
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

class _HBarRow extends StatelessWidget {
  final String label;
  final int count;
  final double fraction;
  final Color color;

  const _HBarRow({
    required this.label,
    required this.count,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 7,
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
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

// ── Daily Revenue chart ────────────────────────────────────────────────────────

class _RevenueChartCard extends ConsumerWidget {
  const _RevenueChartCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingsNotifierProvider);
    final dailyRevenue = ref.watch(dashboardDailyRevenueProvider);
    final revenue = ref.watch(dashboardRevenueProvider);

    return _SectionCard(
      title: 'Revenue — Last 30 Days',
      icon: Icons.show_chart_rounded,
      child: bookingsAsync.isLoading
          ? const _LoadingPlaceholder(height: 150)
          : bookingsAsync.hasError
              ? _ErrorPlaceholder(message: bookingsAsync.error.toString())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Month total: ${_currency.format(revenue.thisMonth)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _DailyRevenueChart(data: dailyRevenue),
                  ],
                ),
    );
  }
}

class _DailyRevenueChart extends StatelessWidget {
  final List<DailyRevenueStat> data;
  const _DailyRevenueChart({required this.data});

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final hasData = data.any((d) => d.amount > 0);
    if (!hasData) {
      return const _EmptyPlaceholder(message: 'No completed revenue yet');
    }
    final maxAmount =
        data.map((d) => d.amount).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Peak: ${_currency.format(maxAmount)}',
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.map((stat) {
              final fraction =
                  maxAmount > 0 ? stat.amount / maxAmount : 0.0;
              final today = _isToday(stat.date);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Tooltip(
                    message:
                        '${_dateFmtShort.format(stat.date)}: ${_currency.format(stat.amount)}',
                    child: Container(
                      height: (fraction * 76)
                          .clamp(stat.amount > 0 ? 3.0 : 0.0, 76.0),
                      decoration: BoxDecoration(
                        color: today
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(30, (i) {
            final showLabel = i == 0 || i == 9 || i == 19 || i == 29;
            return Expanded(
              child: showLabel
                  ? Text(
                      _dateFmtShort.format(data[i].date),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                      textAlign:
                          i == 29 ? TextAlign.right : TextAlign.left,
                      overflow: TextOverflow.visible,
                    )
                  : const SizedBox.shrink(),
            );
          }),
        ),
      ],
    );
  }
}

// ── Charts row 2: Top Services + Vendor Performance ───────────────────────────

class _ChartsRow2 extends ConsumerWidget {
  const _ChartsRow2();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > AppBreakpoints.mobile;
        if (wide) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _TopServicesCard()),
              SizedBox(width: 16),
              Expanded(child: _VendorPerfCard()),
            ],
          );
        }
        return const Column(
          children: [
            _TopServicesCard(),
            SizedBox(height: 16),
            _VendorPerfCard(),
          ],
        );
      },
    );
  }
}

class _TopServicesCard extends ConsumerWidget {
  const _TopServicesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingsNotifierProvider);
    final topServices = ref.watch(dashboardTopServicesProvider);

    return _SectionCard(
      title: 'Top Services (Completed)',
      icon: Icons.star_rounded,
      child: bookingsAsync.isLoading
          ? const _LoadingPlaceholder(height: 120)
          : bookingsAsync.hasError
              ? _ErrorPlaceholder(message: bookingsAsync.error.toString())
              : topServices.isEmpty
                  ? const _EmptyPlaceholder(
                      message: 'No completed bookings yet')
                  : Column(children: () {
                      final maxCount = topServices
                          .map((s) => s.bookingCount)
                          .reduce((a, b) => a > b ? a : b);
                      return topServices
                          .map((s) => _HBarRow(
                                label: s.serviceName,
                                count: s.bookingCount,
                                fraction: maxCount > 0
                                    ? s.bookingCount / maxCount
                                    : 0.0,
                                color: const Color(0xFF805AD5),
                              ))
                          .toList();
                    }()),
    );
  }
}

class _VendorPerfCard extends ConsumerWidget {
  const _VendorPerfCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingsNotifierProvider);
    final vendorPerf = ref.watch(dashboardVendorPerfProvider);

    return _SectionCard(
      title: 'Vendor Performance',
      icon: Icons.leaderboard_rounded,
      child: bookingsAsync.isLoading
          ? const _LoadingPlaceholder(height: 120)
          : bookingsAsync.hasError
              ? _ErrorPlaceholder(message: bookingsAsync.error.toString())
              : vendorPerf.isEmpty
                  ? const _EmptyPlaceholder(message: 'No completed jobs yet')
                  : Column(children: () {
                      final maxJobs = vendorPerf
                          .map((v) => v.completedJobs)
                          .reduce((a, b) => a > b ? a : b);
                      return vendorPerf
                          .map((v) => _HBarRow(
                                label: v.vendorName,
                                count: v.completedJobs,
                                fraction: maxJobs > 0
                                    ? v.completedJobs / maxJobs
                                    : 0.0,
                                color: const Color(0xFF38A169),
                              ))
                          .toList();
                    }()),
    );
  }
}

// ── Bottom info row: Vendor Activity + Settlement + Customer Summary ───────────

class _BottomInfoRow extends ConsumerWidget {
  const _BottomInfoRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > AppBreakpoints.mobile;
        if (wide) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _VendorActivityCard()),
              SizedBox(width: 16),
              Expanded(child: _SettlementSummaryCard()),
              SizedBox(width: 16),
              Expanded(child: _CustomerSummaryCard()),
            ],
          );
        }
        return const Column(
          children: [
            _VendorActivityCard(),
            SizedBox(height: 16),
            _SettlementSummaryCard(),
            SizedBox(height: 16),
            _CustomerSummaryCard(),
          ],
        );
      },
    );
  }
}

class _VendorActivityCard extends ConsumerWidget {
  const _VendorActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsLoading = ref.watch(vendorsNotifierProvider).isLoading;
    final teamsLoading = ref.watch(dodoTeamsNotifierProvider).isLoading;
    final activity = ref.watch(dashboardVendorActivityProvider);

    return _SectionCard(
      title: 'Vendor Activity',
      icon: Icons.store_rounded,
      child: (vendorsLoading || teamsLoading)
          ? const _LoadingPlaceholder(height: 110)
          : Column(
              children: [
                _SummaryRow(
                  label: 'Active Vendors',
                  value: '${activity.activeVendors}',
                  color: const Color(0xFF38A169),
                  icon: Icons.store_rounded,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Vendors on Jobs',
                  value: '${activity.vendorsOnJobs}',
                  color: const Color(0xFF805AD5),
                  icon: Icons.work_rounded,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'DODO Teams Total',
                  value: '${activity.totalTeams}',
                  color: const Color(0xFF319795),
                  icon: Icons.groups_rounded,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Available Teams',
                  value: '${activity.availableTeams}',
                  color: const Color(0xFF3182CE),
                  icon: Icons.check_circle_outline_rounded,
                ),
              ],
            ),
    );
  }
}

class _SettlementSummaryCard extends ConsumerWidget {
  const _SettlementSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlementLoading =
        ref.watch(vendorSettlementNotifierProvider).isLoading;
    final totalPending = ref.watch(totalPendingSettlementProvider);
    final vendorsAwaiting = ref.watch(vendorsAwaitingPaymentCountProvider);
    final monthStatsAsync = ref.watch(thisMonthSettlementStatsProvider);

    return _SectionCard(
      title: 'Settlement Summary',
      icon: Icons.payments_rounded,
      child: settlementLoading
          ? const _LoadingPlaceholder(height: 110)
          : Column(
              children: [
                _SummaryRow(
                  label: 'Pending Payments',
                  value: _currencyK.format(totalPending),
                  color: const Color(0xFFDD6B20),
                  icon: Icons.pending_rounded,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Vendors Awaiting',
                  value: '$vendorsAwaiting',
                  color: const Color(0xFF805AD5),
                  icon: Icons.store_rounded,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Settled This Month',
                  value: monthStatsAsync.when(
                    loading: () => '…',
                    error: (e, _) => '—',
                    data: (s) => _currencyK.format(s.$1),
                  ),
                  color: const Color(0xFF38A169),
                  icon: Icons.check_circle_rounded,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Transactions (Month)',
                  value: monthStatsAsync.when(
                    loading: () => '…',
                    error: (e, _) => '—',
                    data: (s) => '${s.$2}',
                  ),
                  color: const Color(0xFF3182CE),
                  icon: Icons.receipt_rounded,
                ),
              ],
            ),
    );
  }
}

class _CustomerSummaryCard extends ConsumerWidget {
  const _CustomerSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersLoading = ref.watch(customersNotifierProvider).isLoading;
    final customerStats = ref.watch(dashboardCustomerStatsProvider);

    return _SectionCard(
      title: 'Customer Summary',
      icon: Icons.people_alt_rounded,
      child: customersLoading
          ? const _LoadingPlaceholder(height: 110)
          : Column(
              children: [
                _SummaryRow(
                  label: 'Total Customers',
                  value: '${customerStats.total}',
                  color: const Color(0xFF3182CE),
                  icon: Icons.people_alt_rounded,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'New This Month',
                  value: '${customerStats.newThisMonth}',
                  color: const Color(0xFF38A169),
                  icon: Icons.person_add_rounded,
                ),
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Returning Customers',
                  value: '${customerStats.returning}',
                  color: const Color(0xFF805AD5),
                  icon: Icons.repeat_rounded,
                ),
              ],
            ),
    );
  }
}

// ── Quick Actions ─────────────────────────────────────────────────────────────

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _QuickActionButton(
              label: 'Bookings',
              icon: Icons.book_online_rounded,
              color: const Color(0xFFDD6B20),
              onTap: () => context.go('/dashboard/bookings'),
            ),
            _QuickActionButton(
              label: 'Add Vendor',
              icon: Icons.store_rounded,
              color: const Color(0xFF38A169),
              onTap: () => context.go('/dashboard/vendors'),
            ),
            _QuickActionButton(
              label: 'DODO Teams',
              icon: Icons.groups_rounded,
              color: const Color(0xFF319795),
              onTap: () => context.go('/dashboard/dodo-teams'),
            ),
            _QuickActionButton(
              label: 'Categories',
              icon: Icons.category_rounded,
              color: const Color(0xFF805AD5),
              onTap: () => context.go('/dashboard/categories'),
            ),
            _QuickActionButton(
              label: 'Settlements',
              icon: Icons.payments_rounded,
              color: const Color(0xFF3182CE),
              onTap: () => context.go('/dashboard/vendor-settlement'),
            ),
            _QuickActionButton(
              label: 'Customers',
              icon: Icons.people_alt_rounded,
              color: const Color(0xFF744210),
              onTap: () => context.go('/dashboard/customers'),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent Activity section ────────────────────────────────────────────────────

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
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > AppBreakpoints.mobile;
            if (wide) {
              return const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _RecentVendors()),
                  SizedBox(width: 16),
                  Expanded(child: _SystemHealthCard()),
                  SizedBox(width: 16),
                  Expanded(child: _RecentCoupons()),
                ],
              );
            }
            return const Column(
              children: [
                _RecentVendors(),
                SizedBox(height: 16),
                _SystemHealthCard(),
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

class _SystemHealthCard extends ConsumerWidget {
  const _SystemHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(dashboardSystemHealthProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final catLoading = ref.watch(categoriesNotifierProvider).isLoading;
    final svcLoading = ref.watch(servicesNotifierProvider).isLoading;
    final cpnLoading = ref.watch(couponsNotifierProvider).isLoading;

    return _SectionCard(
      title: 'System Health',
      icon: Icons.health_and_safety_rounded,
      child: Column(
        children: [
          _SummaryRow(
            label: 'Active Services',
            value: svcLoading ? '…' : '${health.activeServices}',
            color: const Color(0xFF38A169),
            icon: Icons.home_repair_service_rounded,
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Total Services',
            value: svcLoading ? '…' : '${stats.totalServices}',
            color: const Color(0xFF3182CE),
            icon: Icons.list_alt_rounded,
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Active Categories',
            value: catLoading ? '…' : '${health.activeCategories}',
            color: const Color(0xFF805AD5),
            icon: Icons.category_rounded,
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Active Coupons',
            value: cpnLoading ? '…' : '${health.activeCoupons}',
            color: const Color(0xFFDD6B20),
            icon: Icons.local_offer_rounded,
          ),
        ],
      ),
    );
  }
}

class _RecentVendors extends ConsumerWidget {
  const _RecentVendors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vendorsNotifierProvider);

    return _SectionCard(
      title: 'Recent Vendors',
      icon: Icons.store_rounded,
      child: vendorsAsync.when(
        loading: () => const _LoadingPlaceholder(height: 180),
        error: (e, _) => _ErrorPlaceholder(message: e.toString()),
        data: (vendors) {
          if (vendors.isEmpty) {
            return const _EmptyPlaceholder(message: 'No vendors yet');
          }
          return Column(
            children: vendors.take(5).map((v) => _ActivityItem(
                  icon: Icons.store_rounded,
                  iconColor: const Color(0xFF38A169),
                  title: v.businessName,
                  subtitle: v.city.isNotEmpty ? v.city : 'No city',
                  trailing: v.isActive ? 'Active' : 'Inactive',
                  trailingColor: v.isActive
                      ? const Color(0xFF38A169)
                      : const Color(0xFF718096),
                  date: v.createdAt,
                )).toList(),
          );
        },
      ),
    );
  }
}

class _RecentCoupons extends ConsumerWidget {
  const _RecentCoupons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couponsAsync = ref.watch(couponsNotifierProvider);

    return _SectionCard(
      title: 'Recent Coupons',
      icon: Icons.local_offer_rounded,
      child: couponsAsync.when(
        loading: () => const _LoadingPlaceholder(height: 180),
        error: (e, _) => _ErrorPlaceholder(message: e.toString()),
        data: (coupons) {
          if (coupons.isEmpty) {
            return const _EmptyPlaceholder(message: 'No coupons yet');
          }
          return Column(
            children: coupons.take(5).map((c) {
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

// ── Shared: Section card ──────────────────────────────────────────────────────

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
      padding: const EdgeInsets.all(18),
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
              Icon(icon, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Shared: Summary row ───────────────────────────────────────────────────────

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
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Shared: Activity item ─────────────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              if (date case final d?) ...[
                const SizedBox(height: 2),
                Text(
                  _dateFmt.format(d),
                  style: const TextStyle(
                    fontSize: 9,
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

// ── Shared: Placeholders ──────────────────────────────────────────────────────

class _LoadingPlaceholder extends StatelessWidget {
  final double height;
  const _LoadingPlaceholder({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 15, color: AppColors.error),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 11, color: AppColors.error),
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
