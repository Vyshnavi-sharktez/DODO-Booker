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
import '../../../profile/presentation/providers/profile_provider.dart';
import '../../domain/models/dashboard_stats.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/stats_card.dart';

// Black/dark gradient for the welcome hero card.
const _heroStart = Color(0xFF111111);
const _heroEnd   = Color(0xFF2A2A2A);

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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 560;
                final hPad = isWide ? 24.0 : 16.0;

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Welcome ──────────────────────────────────────────────
                      _WelcomeHeader(
                        greeting: greeting,
                        name: vendorName,
                        onRefresh: () => ref.invalidate(dashboardStatsProvider),
                      ),
                      const SizedBox(height: 20),

                      // ── Online / Offline toggle ──────────────────────────────
                      const _OnlineStatusToggle(),
                      const SizedBox(height: 24),

                      // ── Overview stats ───────────────────────────────────────
                      const _SectionHeader('Overview'),
                      const SizedBox(height: 12),
                      _StatsGrid(
                        isWide: isWide,
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
                          StatsCard(
                            label: 'Total Earnings',
                            value: FormatUtils.compact(stats.totalEarnings),
                            icon: Icons.account_balance_wallet_outlined,
                            color: AppColors.success,
                          ),
                          StatsCard(
                            label: "Today's Bookings",
                            value: '${stats.todayCount}',
                            icon: Icons.today_outlined,
                            color: const Color(0xFFDD6B20),
                            onTap: () => context.goNamed(
                              RouteNames.bookings,
                              queryParameters: {'tab': '5'},
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // ── Earnings ─────────────────────────────────────────────
                      const _SectionHeader('Earnings'),
                      const SizedBox(height: 12),
                      _EarningsRow(
                        today: stats.todayEarnings,
                        weekly: stats.weeklyEarnings,
                        monthly: stats.monthlyEarnings,
                      ),
                      const SizedBox(height: 28),

                      // ── Performance ──────────────────────────────────────────
                      const _SectionHeader('Performance'),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
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
                                context.push(RoutePaths.notifications),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // ── Upcoming Schedule ────────────────────────────────────
                      const _SectionHeader('Upcoming Schedule'),
                      const SizedBox(height: 12),
                      stats.upcomingBookings.isEmpty
                          ? const _EmptyUpcoming()
                          : _UpcomingSchedule(
                              bookings: stats.upcomingBookings),
                      const SizedBox(height: 28),

                      // ── Recent Activity ──────────────────────────────────────
                      const _SectionHeader('Recent Activity'),
                      const SizedBox(height: 12),
                      stats.recentBookings.isEmpty
                          ? const _EmptyRecent()
                          : _RecentActivity(bookings: stats.recentBookings),
                      const SizedBox(height: 28),

                      // ── Quick Actions ────────────────────────────────────────
                      const _SectionHeader('Quick Actions'),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: isWide ? 4 : 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: isWide ? 2.8 : 2.4,
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
                                context.push(RoutePaths.notifications),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
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

// ── Responsive stats grid ─────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.isWide, required this.children});

  final bool isWide;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: isWide ? 4 : 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      mainAxisExtent: 128,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

// ── Welcome header ────────────────────────────────────────────────────────────

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.greeting,
    required this.name,
    required this.onRefresh,
  });

  final String greeting;
  final String name;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_heroStart, _heroEnd],
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
                  '$greeting, $name 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'DODO Vendor Portal — '
                      '${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _HeroButton(
            icon: Icons.refresh_rounded,
            onTap: onRefresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
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
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Earnings row — 3 individual cards ─────────────────────────────────────────

class _EarningsRow extends StatelessWidget {
  const _EarningsRow({
    required this.today,
    required this.weekly,
    required this.monthly,
  });

  final double today;
  final double weekly;
  final double monthly;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _EarningsCell(
          label: "Today",
          amount: today,
          icon: Icons.today_rounded,
        ),
        const SizedBox(width: 12),
        _EarningsCell(
          label: 'This Week',
          amount: weekly,
          icon: Icons.date_range_rounded,
        ),
        const SizedBox(width: 12),
        _EarningsCell(
          label: 'This Month',
          amount: monthly,
          icon: Icons.calendar_month_rounded,
        ),
      ],
    );
  }
}

class _EarningsCell extends StatelessWidget {
  const _EarningsCell({
    required this.label,
    required this.amount,
    required this.icon,
  });

  final String label;
  final double amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.textSecondary),
                const Spacer(),
                Icon(
                  Icons.trending_up_rounded,
                  size: 14,
                  color: AppColors.success.withValues(alpha: 0.8),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              FormatUtils.compact(amount),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Performance card ──────────────────────────────────────────────────────────

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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
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
      onTap: () => context.pushNamed(
        RouteNames.bookingDetail,
        pathParameters: {'id': booking.id},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: AppColors.textSecondary,
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
    return _EmptyCard(
      icon: Icons.event_available_outlined,
      label: 'No upcoming bookings',
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
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
      onTap: () => context.pushNamed(
        RouteNames.bookingDetail,
        pathParameters: {'id': booking.id},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
    return _EmptyCard(
      icon: Icons.book_online_outlined,
      label: 'No bookings yet',
    );
  }
}

// ── Shared empty card ─────────────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: AppColors.textHint),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
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

// ── Quick action ──────────────────────────────────────────────────────────────

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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: Clickable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppColors.textHint,
              ),
            ],
          ),
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
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
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

// ── Online / Offline status toggle ────────────────────────────────────────────

class _OnlineStatusToggle extends ConsumerStatefulWidget {
  const _OnlineStatusToggle();

  @override
  ConsumerState<_OnlineStatusToggle> createState() =>
      _OnlineStatusToggleState();
}

class _OnlineStatusToggleState extends ConsumerState<_OnlineStatusToggle> {
  bool _saving = false;

  Future<void> _toggle(String vendorId, bool currentIsOnline) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileDatasourceProvider).updateById(
        id: vendorId,
        fields: {'is_online': !currentIsOnline},
      );
      ref.invalidate(vendorProfileProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(vendorProfileProvider);
    final vendorUser = ref.watch(currentVendorUserProvider);

    final profile = asyncProfile.valueOrNull;
    if (profile == null || vendorUser == null) return const SizedBox.shrink();

    final isOnline = profile.isOnline;
    final statusColor =
        isOnline ? AppColors.success : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOnline
            ? AppColors.success.withValues(alpha: 0.06)
            : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnline
              ? AppColors.success.withValues(alpha: 0.30)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                Text(
                  isOnline
                      ? 'Available for new booking assignments'
                      : 'Not receiving new assignments',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _saving
              ? const SizedBox(
                  width: 52,
                  height: 32,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              : Transform.scale(
                  scale: 1.4,
                  alignment: Alignment.centerRight,
                  child: Switch(
                    value: isOnline,
                    onChanged: (_) => _toggle(vendorUser.id, isOnline),
                    activeThumbColor: AppColors.success,
                  ),
                ),
        ],
      ),
    );
  }
}
