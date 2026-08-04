import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/gps_audit_providers.dart';
import '../../domain/models/gps_cancellation_audit.dart';

enum _DateRangeFilter {
  allTime,
  last7Days,
  last30Days,
  thisMonth,
}

class GpsAnalyticsPage extends ConsumerStatefulWidget {
  const GpsAnalyticsPage({super.key});

  @override
  ConsumerState<GpsAnalyticsPage> createState() => _GpsAnalyticsPageState();
}

class _GpsAnalyticsPageState extends ConsumerState<GpsAnalyticsPage> {
  _DateRangeFilter _dateFilter = _DateRangeFilter.allTime;
  String _selectedVendor = 'all';
  String _selectedStatus = 'all';

  List<GpsCancellationAudit> _applyFilters(List<GpsCancellationAudit> audits) {
    final now = DateTime.now();

    return audits.where((a) {
      // Date filter
      final matchesDate = switch (_dateFilter) {
        _DateRangeFilter.allTime => true,
        _DateRangeFilter.last7Days =>
          a.auditedAt.isAfter(now.subtract(const Duration(days: 7))),
        _DateRangeFilter.last30Days =>
          a.auditedAt.isAfter(now.subtract(const Duration(days: 30))),
        _DateRangeFilter.thisMonth =>
          a.auditedAt.year == now.year && a.auditedAt.month == now.month,
      };

      if (!matchesDate) return false;

      // Vendor filter
      if (_selectedVendor != 'all' && a.vendorId != _selectedVendor) {
        return false;
      }

      // Status filter
      if (_selectedStatus != 'all' && a.auditStatus != _selectedStatus) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auditsAsync = ref.watch(gpsAuditNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.analytics_rounded,
                    color: AppColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'GPS Analytics & Insights',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Performance metrics, false cancellation rates, and vendor GPS distance distribution analytics.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () =>
                      ref.read(gpsAuditNotifierProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh Analytics',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filter Bar
            auditsAsync.maybeWhen(
              data: (allAudits) {
                // Extract unique vendors for vendor filter dropdown
                final vendorMap = <String, String>{};
                for (final a in allAudits) {
                  if (a.vendorBusinessName != null) {
                    vendorMap[a.vendorId] = a.vendorBusinessName!;
                  }
                }

                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Date Range Filter Dropdown
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_DateRangeFilter>(
                          value: _dateFilter,
                          icon: const Icon(Icons.calendar_today_rounded,
                              size: 16),
                          items: const [
                            DropdownMenuItem(
                              value: _DateRangeFilter.allTime,
                              child: Text('All Time'),
                            ),
                            DropdownMenuItem(
                              value: _DateRangeFilter.last7Days,
                              child: Text('Last 7 Days'),
                            ),
                            DropdownMenuItem(
                              value: _DateRangeFilter.last30Days,
                              child: Text('Last 30 Days'),
                            ),
                            DropdownMenuItem(
                              value: _DateRangeFilter.thisMonth,
                              child: Text('This Month'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _dateFilter = val);
                          },
                        ),
                      ),
                    ),

                    // Vendor Filter Dropdown
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedVendor,
                          icon: const Icon(Icons.storefront_rounded, size: 16),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All Vendors'),
                            ),
                            ...vendorMap.entries.map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value,
                                      overflow: TextOverflow.ellipsis),
                                )),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedVendor = val);
                            }
                          },
                        ),
                      ),
                    ),

                    // Status Filter Dropdown
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStatus,
                          icon:
                              const Icon(Icons.filter_list_rounded, size: 16),
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('All Statuses'),
                            ),
                            DropdownMenuItem(
                              value: 'potential_false_cancellation',
                              child: Text('Potential False'),
                            ),
                            DropdownMenuItem(
                              value: 'verified_false_cancellation',
                              child: Text('Verified False'),
                            ),
                            DropdownMenuItem(
                              value: 'verified_valid_cancellation',
                              child: Text('Verified Valid'),
                            ),
                            DropdownMenuItem(
                              value: 'dismissed',
                              child: Text('Dismissed'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedStatus = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),

            // Analytics Body Content
            Expanded(
              child: auditsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error loading GPS analytics: $e',
                      style: const TextStyle(color: AppColors.error)),
                ),
                data: (rawAudits) {
                  final filtered = _applyFilters(rawAudits);
                  final totalCount = filtered.length;

                  // Calculated Metrics
                  final potentialCount = filtered
                      .where(
                          (a) => a.auditStatus == 'potential_false_cancellation')
                      .length;
                  final verifiedFalseCount = filtered
                      .where(
                          (a) => a.auditStatus == 'verified_false_cancellation')
                      .length;
                  final verifiedValidCount = filtered
                      .where(
                          (a) => a.auditStatus == 'verified_valid_cancellation')
                      .length;
                  final dismissedCount = filtered
                      .where((a) => a.auditStatus == 'dismissed').length;

                  final avgDistance = totalCount > 0
                      ? filtered.fold<double>(
                              0.0, (sum, a) => sum + a.minDistanceMeters) /
                          totalCount
                      : 0.0;

                  final falseCancellationRate = totalCount > 0
                      ? ((potentialCount + verifiedFalseCount) /
                          totalCount *
                          100)
                      : 0.0;

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI Metrics Cards Grid
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisCount = constraints.maxWidth > 1100
                                ? 6
                                : constraints.maxWidth > 750
                                    ? 3
                                    : 2;

                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 1.65,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _KpiCard(
                                  title: 'Total Audits',
                                  value: '$totalCount',
                                  subtitle: 'Audited Cancellations',
                                  icon: Icons.list_alt_rounded,
                                  color: AppColors.primary,
                                ),
                                _KpiCard(
                                  title: 'Potential False',
                                  value: '$potentialCount',
                                  subtitle: totalCount > 0
                                      ? '${(potentialCount / totalCount * 100).toStringAsFixed(1)}% of total'
                                      : '0%',
                                  icon: Icons.warning_amber_rounded,
                                  color: AppColors.warning,
                                ),
                                _KpiCard(
                                  title: 'Verified False',
                                  value: '$verifiedFalseCount',
                                  subtitle: totalCount > 0
                                      ? '${(verifiedFalseCount / totalCount * 100).toStringAsFixed(1)}% of total'
                                      : '0%',
                                  icon: Icons.gpp_bad_rounded,
                                  color: AppColors.error,
                                ),
                                _KpiCard(
                                  title: 'Verified Valid',
                                  value: '$verifiedValidCount',
                                  subtitle: totalCount > 0
                                      ? '${(verifiedValidCount / totalCount * 100).toStringAsFixed(1)}% of total'
                                      : '0%',
                                  icon: Icons.verified_user_rounded,
                                  color: AppColors.success,
                                ),
                                _KpiCard(
                                  title: 'Avg Distance',
                                  value: '${avgDistance.toStringAsFixed(1)} m',
                                  subtitle: 'Vendor from Customer',
                                  icon: Icons.straighten_rounded,
                                  color: AppColors.accent,
                                ),
                                _KpiCard(
                                  title: 'False Cancel Rate',
                                  value:
                                      '${falseCancellationRate.toStringAsFixed(1)}%',
                                  subtitle: 'Potential + Verified',
                                  icon: Icons.speed_rounded,
                                  color: const Color(0xFF805AD5),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // Section: Status Breakdown & Distance Distribution
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 900;
                            if (isWide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _StatusBreakdownCard(
                                      total: totalCount,
                                      potential: potentialCount,
                                      verifiedFalse: verifiedFalseCount,
                                      verifiedValid: verifiedValidCount,
                                      dismissed: dismissedCount,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    flex: 6,
                                    child: _DistanceDistributionCard(
                                      audits: filtered,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                _StatusBreakdownCard(
                                  total: totalCount,
                                  potential: potentialCount,
                                  verifiedFalse: verifiedFalseCount,
                                  verifiedValid: verifiedValidCount,
                                  dismissed: dismissedCount,
                                ),
                                const SizedBox(height: 20),
                                _DistanceDistributionCard(
                                  audits: filtered,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // Section: Vendor Risk Leaderboard
                        _VendorRiskLeaderboard(audits: filtered),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── KPI Card Widget ─────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Status Breakdown Distribution Card ──────────────────────────────────────

class _StatusBreakdownCard extends StatelessWidget {
  const _StatusBreakdownCard({
    required this.total,
    required this.potential,
    required this.verifiedFalse,
    required this.verifiedValid,
    required this.dismissed,
  });

  final int total;
  final int potential;
  final int verifiedFalse;
  final int verifiedValid;
  final int dismissed;

  @override
  Widget build(BuildContext context) {
    final pendingCount = total - (potential + verifiedFalse + verifiedValid + dismissed);
    final safeTotal = total > 0 ? total : 1;

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
            children: const [
              Icon(Icons.pie_chart_outline_rounded,
                  size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Audit Decision Distribution',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Proportional Bar
          if (total == 0)
            Container(
              height: 16,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(8),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    if (verifiedFalse > 0)
                      Expanded(
                        flex: verifiedFalse,
                        child: Container(color: AppColors.error),
                      ),
                    if (potential > 0)
                      Expanded(
                        flex: potential,
                        child: Container(color: AppColors.warning),
                      ),
                    if (verifiedValid > 0)
                      Expanded(
                        flex: verifiedValid,
                        child: Container(color: AppColors.success),
                      ),
                    if (dismissed > 0)
                      Expanded(
                        flex: dismissed,
                        child: Container(color: AppColors.textSecondary),
                      ),
                    if (pendingCount > 0)
                      Expanded(
                        flex: pendingCount,
                        child: Container(color: Colors.blue),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),

          // Legend Items
          Column(
            children: [
              _LegendItem(
                label: 'Verified False Cancellation',
                count: verifiedFalse,
                percent: (verifiedFalse / safeTotal * 100),
                color: AppColors.error,
              ),
              const SizedBox(height: 8),
              _LegendItem(
                label: 'Potential False Cancellation',
                count: potential,
                percent: (potential / safeTotal * 100),
                color: AppColors.warning,
              ),
              const SizedBox(height: 8),
              _LegendItem(
                label: 'Verified Valid Cancellation',
                count: verifiedValid,
                percent: (verifiedValid / safeTotal * 100),
                color: AppColors.success,
              ),
              const SizedBox(height: 8),
              _LegendItem(
                label: 'Dismissed Audits',
                count: dismissed,
                percent: (dismissed / safeTotal * 100),
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.count,
    required this.percent,
    required this.color,
  });

  final String label;
  final int count;
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$count (${percent.toStringAsFixed(1)}%)',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Distance Distribution Card ──────────────────────────────────────────────

class _DistanceDistributionCard extends StatelessWidget {
  const _DistanceDistributionCard({required this.audits});

  final List<GpsCancellationAudit> audits;

  @override
  Widget build(BuildContext context) {
    final band1 = audits.where((a) => a.minDistanceMeters < 25).length;
    final band2 = audits
        .where((a) => a.minDistanceMeters >= 25 && a.minDistanceMeters < 50)
        .length;
    final band3 = audits
        .where((a) => a.minDistanceMeters >= 50 && a.minDistanceMeters <= 100)
        .length;
    final band4 = audits.where((a) => a.minDistanceMeters > 100).length;

    final maxVal = [band1, band2, band3, band4]
        .reduce((a, b) => a > b ? a : b);
    final safeMax = maxVal > 0 ? maxVal : 1;

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
            children: const [
              Icon(Icons.bar_chart_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Vendor Distance Bands at Cancellation',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DistanceBarRow(
            label: '< 25 meters (At Location)',
            count: band1,
            fraction: band1 / safeMax,
            color: AppColors.error,
          ),
          const SizedBox(height: 10),
          _DistanceBarRow(
            label: '25 – 50 meters (Near Location)',
            count: band2,
            fraction: band2 / safeMax,
            color: AppColors.warning,
          ),
          const SizedBox(height: 10),
          _DistanceBarRow(
            label: '50 – 100 meters (In Radius)',
            count: band3,
            fraction: band3 / safeMax,
            color: AppColors.accent,
          ),
          const SizedBox(height: 10),
          _DistanceBarRow(
            label: '> 100 meters (Outside Radius)',
            count: band4,
            fraction: band4 / safeMax,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _DistanceBarRow extends StatelessWidget {
  const _DistanceBarRow({
    required this.label,
    required this.count,
    required this.fraction,
    required this.color,
  });

  final String label;
  final int count;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '$count audits',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: AppColors.background,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Vendor Risk Leaderboard ─────────────────────────────────────────────────

class _VendorRiskLeaderboard extends StatelessWidget {
  const _VendorRiskLeaderboard({required this.audits});

  final List<GpsCancellationAudit> audits;

  @override
  Widget build(BuildContext context) {
    // Group audits by vendor
    final vendorStats = <String, ({String name, int total, int falseCount})>{};

    for (final a in audits) {
      final vId = a.vendorId;
      final name = a.vendorBusinessName ?? 'Vendor';
      final isFalse = a.auditStatus == 'potential_false_cancellation' ||
          a.auditStatus == 'verified_false_cancellation';

      final prev = vendorStats[vId] ?? (name: name, total: 0, falseCount: 0);
      vendorStats[vId] = (
        name: name,
        total: prev.total + 1,
        falseCount: prev.falseCount + (isFalse ? 1 : 0),
      );
    }

    final sortedList = vendorStats.values.toList()
      ..sort((a, b) => b.falseCount.compareTo(a.falseCount));

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
            children: const [
              Icon(Icons.leaderboard_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Top Flagged Vendors Leaderboard',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (sortedList.isEmpty)
            const Text('No vendor audit data available',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 600),
                child: DataTable(
                  columnSpacing: 32,
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF7F8FA)),
                  columns: const [
                    DataColumn(label: Text('Vendor Business Name')),
                    DataColumn(label: Text('Total Audits')),
                    DataColumn(label: Text('False Cancellations')),
                    DataColumn(label: Text('Risk Rate')),
                  ],
                  rows: sortedList.take(5).map((stat) {
                    final rate = stat.total > 0
                        ? (stat.falseCount / stat.total * 100)
                        : 0.0;

                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            stat.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        DataCell(Text('${stat.total}')),
                        DataCell(
                          Text(
                            '${stat.falseCount}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: rate > 50
                                  ? AppColors.error.withValues(alpha: 0.12)
                                  : AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${rate.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: rate > 50
                                    ? AppColors.error
                                    : AppColors.warning,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
