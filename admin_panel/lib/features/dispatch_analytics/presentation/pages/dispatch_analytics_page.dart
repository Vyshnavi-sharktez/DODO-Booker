import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../bookings/application/providers/dispatch_providers.dart';
import '../../../bookings/domain/models/booking.dart';
import '../../../bookings/domain/models/booking_assignment_record.dart';
import '../../../vendor_tiers/application/providers/vendor_tiers_providers.dart';
import '../../../vendor_tiers/domain/models/vendor_tier.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../application/csv_downloader.dart';

final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
final _exportDateFmt = DateFormat('yyyyMMdd_HHmmss');

class DispatchAnalyticsPage extends ConsumerStatefulWidget {
  const DispatchAnalyticsPage({super.key});

  @override
  ConsumerState<DispatchAnalyticsPage> createState() =>
      _DispatchAnalyticsPageState();
}

class _DispatchAnalyticsPageState
    extends ConsumerState<DispatchAnalyticsPage> {
  String _searchQuery = '';
  String _selectedDateRange = 'All Time'; // 'All Time', 'Today', 'Last 7 Days', 'Last 30 Days'
  String _selectedStatusFilter = 'All'; // 'All', 'accepted', 'rejected', 'timed_out', 'pending'
  String _selectedTierFilter = 'All'; // 'All' or tier.id

  Future<void> _exportCsv(
    List<BookingAssignmentRecord> records,
    int configuredTimeoutSeconds,
  ) async {
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No dispatch records to export.')),
      );
      return;
    }

    final buf = StringBuffer();
    buf.writeln(
      'Booking Number,Attempt Number,Vendor Name,Tier Name,Assigned At,Responded At,Status,Response Time (seconds),Rejection Reason',
    );

    for (final r in records) {
      final bNum = _escapeCsv(r.bookingNumber ?? r.bookingId);
      final attempt = r.attemptNumber;
      final vendorName = _escapeCsv(r.vendor?.businessName ?? 'Vendor #${r.vendorId ?? ''}');
      final tierName = _escapeCsv(r.vendorTier?.name ?? 'Tier ${r.tierPriority ?? r.attemptNumber}');
      final assignedAt = _escapeCsv(r.assignedAt.toIso8601String());
      final respondedAt = _escapeCsv(r.respondedAt?.toIso8601String() ?? '');
      final status = _escapeCsv(r.status);
      final respSecs = (r.respondedAt != null || r.status == 'timed_out')
          ? _getEffectiveResponseSeconds(r, configuredTimeoutSeconds).toString()
          : '';
      final reason = _escapeCsv(r.rejectionReason ?? '');

      buf.writeln(
        '$bNum,$attempt,$vendorName,$tierName,$assignedAt,$respondedAt,$status,$respSecs,$reason',
      );
    }

    final filename = 'dispatch_analytics_report_${_exportDateFmt.format(DateTime.now())}.csv';
    await downloadCsv(buf.toString(), filename);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${records.length} records to $filename')),
      );
    }
  }

  int _getEffectiveResponseSeconds(
    BookingAssignmentRecord r,
    int configuredTimeoutSeconds,
  ) {
    if (r.status == 'timed_out') {
      if (r.respondedAt != null) {
        final diff = r.respondedAt!.difference(r.assignedAt).inSeconds.abs();
        if (diff > 0 && diff <= configuredTimeoutSeconds) {
          return diff;
        }
      }
      return configuredTimeoutSeconds;
    }
    if (r.respondedAt == null) return 0;
    final diff = r.respondedAt!.difference(r.assignedAt).inSeconds.abs();
    return diff > configuredTimeoutSeconds ? configuredTimeoutSeconds : diff;
  }

  String _escapeCsv(String input) {
    if (input.contains(',') || input.contains('"') || input.contains('\n')) {
      final escaped = input.replaceAll('"', '""');
      return '"$escaped"';
    }
    return input;
  }

  List<BookingAssignmentRecord> _filterRecords(
    List<BookingAssignmentRecord> records,
  ) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    return records.where((r) {
      final localAssignedAt = r.assignedAt.toLocal();

      // Date range filter
      if (_selectedDateRange == 'Today') {
        if (localAssignedAt.isBefore(startOfDay)) return false;
      } else if (_selectedDateRange == 'Last 7 Days') {
        final cutoff = startOfDay.subtract(const Duration(days: 6));
        if (localAssignedAt.isBefore(cutoff)) return false;
      } else if (_selectedDateRange == 'Last 30 Days') {
        final cutoff = startOfDay.subtract(const Duration(days: 29));
        if (localAssignedAt.isBefore(cutoff)) return false;
      }

      // Status filter (case-insensitive)
      if (_selectedStatusFilter != 'All') {
        final targetStatus = _selectedStatusFilter.toLowerCase();
        final recordStatus = r.status.toLowerCase();
        if (recordStatus != targetStatus) return false;
      }

      // Tier filter
      if (_selectedTierFilter != 'All' && r.tierId != _selectedTierFilter) {
        return false;
      }

      // Search query filter (booking # or vendor name)
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final bookingMatch = (r.bookingNumber ?? r.bookingId).toLowerCase().contains(q);
        final vendorMatch = (r.vendor?.businessName ?? '').toLowerCase().contains(q);
        if (!bookingMatch && !vendorMatch) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(allBookingAssignmentsHistoryProvider);
    final bookingsList = ref.watch(bookingsNotifierProvider).valueOrNull ?? [];
    final tiersList = ref.watch(vendorTiersNotifierProvider).valueOrNull ?? [];
    final vendorsList = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];

    final dispatchSettings = ref.watch(dispatchSettingsNotifierProvider).valueOrNull;
    final timeoutSeconds = dispatchSettings?.tierTimeoutSeconds ?? 46;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Bar ───────────────────────────────────────────────
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dispatch Analytics',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Performance metrics, tier-wise breakdown, vendor response times, and full attempt audit logs.',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.invalidate(allBookingAssignmentsHistoryProvider);
                    ref.invalidate(bookingsNotifierProvider);
                    ref.invalidate(vendorTiersNotifierProvider);
                    ref.invalidate(vendorsNotifierProvider);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                historyAsync.when(
                  data: (records) => ElevatedButton.icon(
                    onPressed: () => _exportCsv(_filterRecords(records), timeoutSeconds),
                    icon: const Icon(Icons.file_download_rounded, size: 18),
                    label: const Text('Export CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Analytics Body ───────────────────────────────────────────────
            historyAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(60),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, st) => Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.error),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Failed to load dispatch history: $err',
                          style: const TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              ),
              data: (allRecords) {
                final filteredRecords = _filterRecords(allRecords);

                // Compute KPI Metrics strictly from booking_assignments (filteredRecords)
                final totalAttempts = filteredRecords.length;

                // Unique bookings auto-dispatched
                final uniqueBookingIds =
                    filteredRecords.map((r) => r.bookingId).toSet();
                final totalAutoDispatchedBookings = uniqueBookingIds.length;

                // Successful bookings (accepted)
                final acceptedAttempts = filteredRecords
                    .where((r) => r.status.toLowerCase() == 'accepted')
                    .toList();
                final successfulBookingsCount = acceptedAttempts
                    .map((r) => r.bookingId)
                    .toSet()
                    .length;

                // No Vendor Accepted / Exhausted Dispatches
                final exhaustedBookingIds = uniqueBookingIds.where((bId) {
                  final attempts = filteredRecords.where((r) => r.bookingId == bId);
                  final hasAccepted = attempts.any((r) => r.status.toLowerCase() == 'accepted');
                  if (hasAccepted) return false;
                  final isExhaustedInBookings = bookingsList.any((b) => b.id == bId && b.dispatchStatus == 'exhausted');
                  final hasTimedOutOrRejected = attempts.any((r) => r.status.toLowerCase() == 'timed_out' || r.status.toLowerCase() == 'rejected');
                  return isExhaustedInBookings || hasTimedOutOrRejected;
                }).toSet();
                final noVendorAcceptedCount = exhaustedBookingIds.length;

                final rejectedAttemptsCount = filteredRecords
                    .where((r) => r.status.toLowerCase() == 'rejected')
                    .length;
                final timedOutAttemptsCount = filteredRecords
                    .where((r) => r.status.toLowerCase() == 'timed_out')
                    .length;

                final acceptanceRate = totalAttempts > 0
                    ? (acceptedAttempts.length / totalAttempts) * 100
                    : 0.0;
                final rejectionRate = totalAttempts > 0
                    ? (rejectedAttemptsCount / totalAttempts) * 100
                    : 0.0;
                final timeoutRate = totalAttempts > 0
                    ? (timedOutAttemptsCount / totalAttempts) * 100
                    : 0.0;

                // Avg response time
                final respondedRecords = filteredRecords
                    .where((r) => r.respondedAt != null || r.status.toLowerCase() == 'timed_out')
                    .toList();
                final totalRespSeconds = respondedRecords.fold<int>(
                  0,
                  (sum, r) => sum + _getEffectiveResponseSeconds(r, timeoutSeconds),
                );
                final avgRespSeconds = respondedRecords.isNotEmpty
                    ? (totalRespSeconds / respondedRecords.length).round()
                    : 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Summary KPI Cards ──────────────────────────────────
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final crossAxisCount = width > 1100
                            ? 5
                            : (width > 700 ? 3 : 2);
                        return GridView.count(
                          crossAxisCount: crossAxisCount,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.6,
                          children: [
                            _KpiCard(
                              title: 'Total Dispatches',
                              value: '$totalAutoDispatchedBookings Bookings',
                              subtitle: '$totalAttempts total attempt(s)',
                              icon: Icons.bolt_rounded,
                              color: const Color(0xFF3182CE),
                              bgColor: const Color(0xFFEBF8FF),
                            ),
                            _KpiCard(
                              title: 'Successful Dispatches',
                              value: '$successfulBookingsCount Bookings',
                              subtitle: totalAutoDispatchedBookings > 0
                                  ? '${((successfulBookingsCount / totalAutoDispatchedBookings) * 100).toStringAsFixed(1)}% success rate'
                                  : '0% success rate',
                              icon: Icons.check_circle_rounded,
                              color: const Color(0xFF38A169),
                              bgColor: const Color(0xFFF0FFF4),
                            ),
                            _KpiCard(
                              title: 'No Vendor Accepted',
                              value: '$noVendorAcceptedCount Bookings',
                              subtitle: totalAutoDispatchedBookings > 0
                                  ? '${((noVendorAcceptedCount / totalAutoDispatchedBookings) * 100).toStringAsFixed(1)}% exhausted'
                                  : '0% exhausted',
                              icon: Icons.error_outline_rounded,
                              color: const Color(0xFFE53E3E),
                              bgColor: const Color(0xFFFFF5F5),
                            ),
                            _KpiCard(
                              title: 'Avg Response Time',
                              value: _formatSeconds(avgRespSeconds),
                              subtitle: '${respondedRecords.length} responded attempt(s)',
                              icon: Icons.timer_rounded,
                              color: const Color(0xFFD69E2E),
                              bgColor: const Color(0xFFFEFCBF),
                            ),
                            _KpiCard(
                              title: 'Attempt Outcome Rates',
                              value: '${acceptanceRate.toStringAsFixed(1)}% Accept',
                              subtitle:
                                  'Rejection: ${rejectionRate.toStringAsFixed(1)}% | Timeout: ${timeoutRate.toStringAsFixed(1)}%',
                              icon: Icons.donut_large_rounded,
                              color: const Color(0xFF805AD5),
                              bgColor: const Color(0xFFFAF5FF),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),

                    // ── Tier-Wise Analytics ────────────────────────────────
                    _SectionTitle(
                      title: 'Tier-Wise Performance Analytics',
                      subtitle: 'Breakdown of dispatch attempts, acceptances, timeouts, and response times across vendor tiers.',
                    ),
                    const SizedBox(height: 12),
                    _TierAnalyticsCard(
                      records: filteredRecords,
                      tiers: tiersList,
                      configuredTimeoutSeconds: timeoutSeconds,
                    ),
                    const SizedBox(height: 28),

                    // ── Vendor Performance Analytics ──────────────────────
                    _SectionTitle(
                      title: 'Vendor Response & Acceptance Leaderboard',
                      subtitle: 'Per-vendor offer counts, acceptance rates, rejection rates, and average response times.',
                    ),
                    const SizedBox(height: 12),
                    _VendorAnalyticsCard(
                      records: filteredRecords,
                      vendors: vendorsList,
                      configuredTimeoutSeconds: timeoutSeconds,
                    ),
                    const SizedBox(height: 28),

                    // ── Dispatch History Table ─────────────────────────────
                    _SectionTitle(
                      title: 'Dispatch History Audit Log',
                      subtitle: 'Comprehensive record of all auto-dispatch assignment attempts.',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Filters row
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 260,
                                  child: AdminSearchBar(
                                    hintText: 'Search booking # or vendor...',
                                    onChanged: (v) =>
                                        setState(() => _searchQuery = v),
                                  ),
                                ),
                                _FilterDropdown<String>(
                                  label: 'Date Range',
                                  value: _selectedDateRange,
                                  items: const [
                                    'All Time',
                                    'Today',
                                    'Last 7 Days',
                                    'Last 30 Days'
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedDateRange = val);
                                    }
                                  },
                                ),
                                _FilterDropdown<String>(
                                  label: 'Status',
                                  value: _selectedStatusFilter,
                                  items: const [
                                    'All',
                                    'accepted',
                                    'rejected',
                                    'timed_out',
                                    'pending'
                                  ],
                                  itemLabels: const {
                                    'All': 'All Statuses',
                                    'accepted': 'Accepted',
                                    'rejected': 'Rejected',
                                    'timed_out': 'Timed Out',
                                    'pending': 'Pending',
                                  },
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedStatusFilter = val);
                                    }
                                  },
                                ),
                                _FilterDropdown<String>(
                                  label: 'Tier',
                                  value: _selectedTierFilter,
                                  items: [
                                    'All',
                                    ...tiersList.map((t) => t.id),
                                  ],
                                  itemLabels: {
                                    'All': 'All Tiers',
                                    for (final t in tiersList)
                                      t.id: '${t.name} (P${t.priority})',
                                  },
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => _selectedTierFilter = val);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Table Header
                          Container(
                            color: AppColors.background,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: const Row(
                              children: [
                                _Th('Booking #', flex: 3),
                                _Th('Attempt', flex: 2),
                                _Th('Vendor', flex: 4),
                                _Th('Tier', flex: 3),
                                _Th('Assigned At', flex: 4),
                                _Th('Status', flex: 3),
                                _Th('Response Time', flex: 3),
                                _Th('Reason / Notes', flex: 4),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          if (filteredRecords.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(
                                child: Text(
                                  'No dispatch attempt records match the selected filters.',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filteredRecords.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final r = filteredRecords[index];
                                final (statusLabel, statusColor, statusBg) =
                                    _statusBadgeData(r.status);
                                final vendorName = r.vendor?.businessName ??
                                    (r.vendorId != null && r.vendorId!.length > 8
                                        ? '${r.vendorId!.substring(0, 8)}…'
                                        : r.vendorId ?? '—');
                                final tierName = r.vendorTier?.name ??
                                    (r.tierPriority != null
                                        ? 'Tier ${r.tierPriority}'
                                        : '—');
                                final respSecs = (r.respondedAt != null || r.status == 'timed_out')
                                    ? _getEffectiveResponseSeconds(r, timeoutSeconds)
                                    : null;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  child: Row(
                                    children: [
                                      // Booking #
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          r.bookingNumber?.isNotEmpty == true
                                              ? '#${r.bookingNumber}'
                                              : _truncateId(r.bookingId),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.accent,
                                          ),
                                        ),
                                      ),

                                      // Attempt #
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          '#${r.attemptNumber}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),

                                      // Vendor
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          vendorName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),

                                      // Tier
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          tierName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),

                                      // Assigned At
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          _dateFmt.format(r.assignedAt.toLocal()),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),

                                      // Status badge
                                      Expanded(
                                        flex: 3,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 9, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: statusBg,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              statusLabel,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: statusColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Response time
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          respSecs != null
                                              ? _formatSeconds(respSecs)
                                              : (r.status == 'pending'
                                                  ? 'In progress'
                                                  : '—'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),

                                      // Rejection reason
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          r.rejectionReason?.isNotEmpty == true
                                              ? r.rejectionReason!
                                              : '—',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: r.rejectionReason?.isNotEmpty == true
                                                ? AppColors.error
                                                : AppColors.textSecondary,
                                            fontStyle: r.rejectionReason?.isNotEmpty == true
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  (String label, Color color, Color bg) _statusBadgeData(String status) =>
      switch (status) {
        'accepted'  => ('Accepted', const Color(0xFF38A169), const Color(0xFFF0FFF4)),
        'rejected'  => ('Rejected', const Color(0xFFE53E3E), const Color(0xFFFFF5F5)),
        'timed_out' => ('Timed Out', const Color(0xFFDD6B20), const Color(0xFFFEEBC8)),
        'pending'   => ('Pending', const Color(0xFF3182CE), const Color(0xFFEBF8FF)),
        _           => (status, const Color(0xFF718096), const Color(0xFFEDF2F7)),
      };

  String _formatSeconds(int secs) {
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return '${mins}m ${rem}s';
  }

  String _truncateId(String id) =>
      id.length > 8 ? '${id.substring(0, 8)}…' : id;
}

// ── Widget Components ────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
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
        ],
      ),
    );
  }
}

class _TierAnalyticsCard extends StatelessWidget {
  final List<BookingAssignmentRecord> records;
  final List<VendorTier> tiers;
  final int configuredTimeoutSeconds;

  const _TierAnalyticsCard({
    required this.records,
    required this.tiers,
    this.configuredTimeoutSeconds = 46,
  });

  int _getEffectiveResponseSeconds(BookingAssignmentRecord r) {
    if (r.status == 'timed_out') {
      if (r.respondedAt != null) {
        final diff = r.respondedAt!.difference(r.assignedAt).inSeconds.abs();
        if (diff > 0 && diff <= configuredTimeoutSeconds) {
          return diff;
        }
      }
      return configuredTimeoutSeconds;
    }
    if (r.respondedAt == null) return 0;
    final diff = r.respondedAt!.difference(r.assignedAt).inSeconds.abs();
    return diff > configuredTimeoutSeconds ? configuredTimeoutSeconds : diff;
  }

  @override
  Widget build(BuildContext context) {
    // Map records by tierId or tierPriority
    final tierStats = <String, Map<String, dynamic>>{};

    for (final r in records) {
      final key = r.tierId ?? 'unranked_${r.tierPriority ?? 999}';
      final tierName = r.vendorTier?.name ?? 'Tier ${r.tierPriority ?? 'Unranked'}';

      tierStats.putIfAbsent(key, () => {
        'name': tierName,
        'priority': r.tierPriority ?? 999,
        'total': 0,
        'accepted': 0,
        'rejected': 0,
        'timed_out': 0,
        'resp_seconds': 0,
        'resp_count': 0,
      });

      final stat = tierStats[key]!;
      stat['total'] = (stat['total'] as int) + 1;

      if (r.status == 'accepted') stat['accepted'] = (stat['accepted'] as int) + 1;
      if (r.status == 'rejected') stat['rejected'] = (stat['rejected'] as int) + 1;
      if (r.status == 'timed_out') stat['timed_out'] = (stat['timed_out'] as int) + 1;

      if (r.respondedAt != null || r.status == 'timed_out') {
        final secs = _getEffectiveResponseSeconds(r);
        stat['resp_seconds'] = (stat['resp_seconds'] as int) + secs;
        stat['resp_count'] = (stat['resp_count'] as int) + 1;
      }
    }

    final sortedStats = tierStats.values.toList()
      ..sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: const Row(
              children: [
                _Th('Tier Name', flex: 4),
                _Th('Priority', flex: 2),
                _Th('Total Offers', flex: 3),
                _Th('Acceptance Rate', flex: 3),
                _Th('Rejection Rate', flex: 3),
                _Th('Timeout Rate', flex: 3),
                _Th('Avg Response', flex: 3),
              ],
            ),
          ),
          const Divider(height: 1),
          if (sortedStats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No tier dispatch data available.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedStats.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = sortedStats[index];
                final total = s['total'] as int;
                final accepted = s['accepted'] as int;
                final rejected = s['rejected'] as int;
                final timedOut = s['timed_out'] as int;
                final respCount = s['resp_count'] as int;
                final respSecs = s['resp_seconds'] as int;

                final accRate = total > 0 ? (accepted / total) * 100 : 0.0;
                final rejRate = total > 0 ? (rejected / total) * 100 : 0.0;
                final toutRate = total > 0 ? (timedOut / total) * 100 : 0.0;
                final avgRespSecs = respCount > 0 ? (respSecs / respCount).round() : 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          s['name'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'P${s['priority']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '$total offers',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${accRate.toStringAsFixed(1)}% ($accepted)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF38A169),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${rejRate.toStringAsFixed(1)}% ($rejected)',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFE53E3E),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${toutRate.toStringAsFixed(1)}% ($timedOut)',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFDD6B20),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          respCount > 0 ? _formatSeconds(avgRespSecs) : '—',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatSeconds(int secs) {
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return '${mins}m ${rem}s';
  }
}

class _VendorAnalyticsCard extends StatelessWidget {
  final List<BookingAssignmentRecord> records;
  final List<Vendor> vendors;
  final int configuredTimeoutSeconds;

  const _VendorAnalyticsCard({
    required this.records,
    required this.vendors,
    this.configuredTimeoutSeconds = 46,
  });

  int _getEffectiveResponseSeconds(BookingAssignmentRecord r) {
    if (r.status == 'timed_out') {
      if (r.respondedAt != null) {
        final diff = r.respondedAt!.difference(r.assignedAt).inSeconds.abs();
        if (diff > 0 && diff <= configuredTimeoutSeconds) {
          return diff;
        }
      }
      return configuredTimeoutSeconds;
    }
    if (r.respondedAt == null) return 0;
    final diff = r.respondedAt!.difference(r.assignedAt).inSeconds.abs();
    return diff > configuredTimeoutSeconds ? configuredTimeoutSeconds : diff;
  }

  @override
  Widget build(BuildContext context) {
    final vendorStats = <String, Map<String, dynamic>>{};

    for (final r in records) {
      final vId = r.vendorId ?? 'unknown';
      final vName = r.vendor?.businessName ??
          vendors.where((v) => v.id == vId).firstOrNull?.businessName ??
          (vId.length > 8 ? '${vId.substring(0, 8)}…' : vId);

      vendorStats.putIfAbsent(vId, () => {
        'name': vName,
        'tier': r.vendorTier?.name ?? 'Tier ${r.tierPriority ?? '—'}',
        'total': 0,
        'accepted': 0,
        'rejected': 0,
        'timed_out': 0,
        'resp_seconds': 0,
        'resp_count': 0,
      });

      final stat = vendorStats[vId]!;
      stat['total'] = (stat['total'] as int) + 1;

      if (r.status == 'accepted') stat['accepted'] = (stat['accepted'] as int) + 1;
      if (r.status == 'rejected') stat['rejected'] = (stat['rejected'] as int) + 1;
      if (r.status == 'timed_out') stat['timed_out'] = (stat['timed_out'] as int) + 1;

      if (r.respondedAt != null || r.status == 'timed_out') {
        final secs = _getEffectiveResponseSeconds(r);
        stat['resp_seconds'] = (stat['resp_seconds'] as int) + secs;
        stat['resp_count'] = (stat['resp_count'] as int) + 1;
      }
    }

    final sortedStats = vendorStats.values.toList()
      ..sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: const Row(
              children: [
                _Th('Vendor Name', flex: 4),
                _Th('Tier', flex: 3),
                _Th('Total Offers', flex: 3),
                _Th('Accepted', flex: 3),
                _Th('Rejected', flex: 3),
                _Th('Timed Out', flex: 3),
                _Th('Avg Response', flex: 3),
              ],
            ),
          ),
          const Divider(height: 1),
          if (sortedStats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No vendor dispatch performance records.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedStats.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = sortedStats[index];
                final total = s['total'] as int;
                final accepted = s['accepted'] as int;
                final rejected = s['rejected'] as int;
                final timedOut = s['timed_out'] as int;
                final respCount = s['resp_count'] as int;
                final respSecs = s['resp_seconds'] as int;

                final accRate = total > 0 ? (accepted / total) * 100 : 0.0;
                final avgRespSecs = respCount > 0 ? (respSecs / respCount).round() : 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          s['name'] as String,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          s['tier'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '$total offers',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '$accepted (${accRate.toStringAsFixed(0)}%)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF38A169),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '$rejected',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFE53E3E),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '$timedOut',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFDD6B20),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          respCount > 0 ? _formatSeconds(avgRespSecs) : '—',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatSeconds(int secs) {
    if (secs < 60) return '${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return '${mins}m ${rem}s';
  }
}

class _Th extends StatelessWidget {
  final String label;
  final int flex;

  const _Th(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final Map<T, String>? itemLabels;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    this.itemLabels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          onChanged: onChanged,
          items: items.map((item) {
            final displayText = itemLabels?[item] ?? item.toString();
            return DropdownMenuItem<T>(
              value: item,
              child: Text(displayText),
            );
          }).toList(),
        ),
      ),
    );
  }
}
