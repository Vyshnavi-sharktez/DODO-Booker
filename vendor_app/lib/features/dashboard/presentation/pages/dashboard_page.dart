import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/widgets/clickable.dart';
import '../../../../core/widgets/vendor_scaffold.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../bookings/presentation/widgets/booking_status_badge.dart';
import '../../../notifications/presentation/providers/notifications_provider.dart';
import '../../domain/models/dashboard_stats.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/stats_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final vendor = ref.watch(currentVendorUserProvider);
    final unreadCount = ref.watch(vendorUnreadCountProvider);
    final greeting = _greeting();
    final vendorName = vendor?.name?.split(' ').first ?? 'there';

    debugPrint('[DASH][Page] build — vendor_id=${vendor?.id ?? "NULL"}, '
        'statsAsync=${statsAsync.runtimeType}');
    statsAsync.whenOrNull(
      error: (e, st) => debugPrint('[DASH][Page] error state — $e'),
      data: (d) => debugPrint('[DASH][Page] data state — stats '
          '${d == null ? "null" : "loaded (assigned=${d.assignedCount})"}'),
    );

    return VendorScaffold(
      title: 'Dashboard',
      child: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(dashboardStatsProvider),
        ),
        data: (stats) {
          if (stats == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(dashboardStatsProvider),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Welcome ────────────────────────────────────────────────
                  _WelcomeHeader(greeting: greeting, name: vendorName),
                  const SizedBox(height: 20),

                  // ── Overview ───────────────────────────────────────────────
                  const _SectionHeader('Overview'),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.55,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      StatsCard(
                        label: 'Assigned',
                        value: '${stats.assignedCount}',
                        icon: Icons.assignment_ind_outlined,
                        color: AppColors.statusAssigned,
                        onTap: () => context.goNamed(
                          RouteNames.bookings,
                          queryParameters: {'tab': '0'},
                        ),
                      ),
                      StatsCard(
                        label: 'In Progress',
                        value: '${stats.inProgressCount}',
                        icon: Icons.pending_actions_outlined,
                        color: AppColors.statusInProgress,
                        onTap: () => context.goNamed(
                          RouteNames.bookings,
                          queryParameters: {'tab': '1'},
                        ),
                      ),
                      StatsCard(
                        label: 'Completed',
                        value: '${stats.completedCount}',
                        icon: Icons.check_circle_outline_rounded,
                        color: AppColors.statusCompleted,
                        onTap: () => context.goNamed(
                          RouteNames.bookings,
                          queryParameters: {'tab': '2'},
                        ),
                      ),
                      StatsCard(
                        label: 'Rejected',
                        value: '${stats.rejectedCount}',
                        icon: Icons.cancel_outlined,
                        color: AppColors.error,
                        onTap: () => context.goNamed(
                          RouteNames.bookings,
                          queryParameters: {'tab': '3'},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: StatsCard(
                          label: 'Total Earnings',
                          value: FormatUtils.compact(stats.totalEarnings),
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatsCard(
                          label: "Today's Bookings",
                          value: '${stats.todayCount}',
                          icon: Icons.today_outlined,
                          color: const Color(0xFFDD6B20),
                          onTap: () => context.goNamed(
                            RouteNames.bookings,
                            queryParameters: {'tab': '5'},
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Earnings ───────────────────────────────────────────────
                  const _SectionHeader('Earnings'),
                  const SizedBox(height: 10),
                  _EarningsCard(
                    today: stats.todayEarnings,
                    weekly: stats.weeklyEarnings,
                    monthly: stats.monthlyEarnings,
                  ),
                  const SizedBox(height: 24),

                  // ── Performance ────────────────────────────────────────────
                  const _SectionHeader('Performance'),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 0,
                    childAspectRatio: 1.1,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _PerformanceCard(
                        label: 'Completion',
                        value:
                            '${stats.completionRate.toStringAsFixed(1)}%',
                        icon: Icons.check_circle_outline_rounded,
                        color: AppColors.success,
                      ),
                      _PerformanceCard(
                        label: 'Rejection',
                        value:
                            '${stats.rejectionRate.toStringAsFixed(1)}%',
                        icon: Icons.cancel_outlined,
                        color: AppColors.error,
                      ),
                      _PerformanceCard(
                        label: 'Unread',
                        value: '$unreadCount',
                        icon: Icons.notifications_outlined,
                        color: AppColors.warning,
                        onTap: () =>
                            context.go(RoutePaths.notifications),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Upcoming Schedule ──────────────────────────────────────
                  const _SectionHeader('Upcoming Schedule'),
                  const SizedBox(height: 10),
                  stats.upcomingBookings.isEmpty
                      ? const _EmptyUpcoming()
                      : _UpcomingSchedule(
                          bookings: stats.upcomingBookings),
                  const SizedBox(height: 24),

                  // ── Recent Activity ────────────────────────────────────────
                  const _SectionHeader('Recent Activity'),
                  const SizedBox(height: 10),
                  stats.recentBookings.isEmpty
                      ? const _EmptyRecent()
                      : _RecentActivity(bookings: stats.recentBookings),
                  const SizedBox(height: 24),

                  // ── Quick Actions ──────────────────────────────────────────
                  const _SectionHeader('Quick Actions'),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _QuickAction(
                        label: 'Manage Services',
                        icon: Icons.home_repair_service_outlined,
                        onTap: () => context.go(RoutePaths.services),
                      ),
                      _QuickAction(
                        label: 'View Bookings',
                        icon: Icons.book_online_outlined,
                        onTap: () => context.go(RoutePaths.bookings),
                      ),
                      _QuickAction(
                        label: 'Edit Profile',
                        icon: Icons.person_outline_rounded,
                        onTap: () => context.go(RoutePaths.profile),
                      ),
                      _QuickAction(
                        label: 'Notifications',
                        icon: Icons.notifications_outlined,
                        onTap: () =>
                            context.go(RoutePaths.notifications),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

// ── Welcome header ────────────────────────────────────────────────────────────

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.greeting, required this.name});

  final String greeting;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF4285F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting, $name!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

// ── Earnings card (Today / This Week / This Month) ────────────────────────────

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({
    required this.today,
    required this.weekly,
    required this.monthly,
  });

  final double today;
  final double weekly;
  final double monthly;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _EarningsColumn(label: 'Today', amount: today),
          _divider(),
          _EarningsColumn(label: 'This Week', amount: weekly),
          _divider(),
          _EarningsColumn(label: 'This Month', amount: monthly),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 38,
        color: AppColors.border,
        margin: const EdgeInsets.symmetric(horizontal: 10),
      );
}

class _EarningsColumn extends StatelessWidget {
  const _EarningsColumn({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            FormatUtils.compact(amount),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Performance card (compact 3-column) ──────────────────────────────────────

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Upcoming schedule ─────────────────────────────────────────────────────────

class _UpcomingSchedule extends StatelessWidget {
  const _UpcomingSchedule({required this.bookings});
  final List<DashboardBooking> bookings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: bookings.length,
          separatorBuilder: (ctx, i) =>
              const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (_, i) => _UpcomingTile(booking: bookings[i]),
        ),
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.booking});
  final DashboardBooking booking;

  @override
  Widget build(BuildContext context) {
    final service = booking.service?.isNotEmpty == true
        ? booking.service!
        : '#${booking.bookingNumber}';
    final dateLabel = booking.serviceDate != null
        ? DateFormat('EEE, d MMM').format(booking.serviceDate!)
        : '—';

    return InkWell(
      onTap: () => context.goNamed(
        RouteNames.bookingDetail,
        pathParameters: {'id': booking.id},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            BookingStatusBadge(status: booking.status),
          ],
        ),
      ),
    );
  }
}

class _EmptyUpcoming extends StatelessWidget {
  const _EmptyUpcoming();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available_outlined,
                size: 36, color: AppColors.textHint),
            SizedBox(height: 8),
            Text(
              'No upcoming bookings',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent activity ───────────────────────────────────────────────────────────

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.bookings});
  final List<DashboardBooking> bookings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: bookings.length,
          separatorBuilder: (ctx, i) =>
              const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (_, i) => _RecentBookingTile(booking: bookings[i]),
        ),
      ),
    );
  }
}

class _RecentBookingTile extends StatelessWidget {
  const _RecentBookingTile({required this.booking});
  final DashboardBooking booking;

  @override
  Widget build(BuildContext context) {
    final service = booking.service?.isNotEmpty == true
        ? booking.service!
        : '#${booking.bookingNumber}';
    final date = booking.serviceDate ?? booking.createdAt;
    final dateLabel = date != null ? DateFormat('d MMM').format(date) : '—';

    return InkWell(
      onTap: () => context.goNamed(
        RouteNames.bookingDetail,
        pathParameters: {'id': booking.id},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '#${booking.bookingNumber}  ·  $dateLabel',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  FormatUtils.currency(booking.amount),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                BookingStatusBadge(status: booking.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_online_outlined,
                size: 36, color: AppColors.textHint),
            SizedBox(height: 8),
            Text(
              'No bookings yet',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick action button ───────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Clickable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            const Text(
              'Failed to load dashboard',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
