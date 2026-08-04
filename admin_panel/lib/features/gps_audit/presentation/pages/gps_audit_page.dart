import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/gps_audit_providers.dart';
import '../../domain/models/gps_cancellation_audit.dart';
import '../widgets/gps_audit_details_dialog.dart';

enum _StatusFilter {
  all,
  potential,
  verifiedFalse,
  verifiedValid,
  dismissed,
}

class GpsAuditPage extends ConsumerStatefulWidget {
  const GpsAuditPage({super.key});

  @override
  ConsumerState<GpsAuditPage> createState() => _GpsAuditPageState();
}

class _GpsAuditPageState extends ConsumerState<GpsAuditPage> {
  _StatusFilter _filter = _StatusFilter.all;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GpsCancellationAudit> _applyFilters(List<GpsCancellationAudit> audits) {
    return audits.where((a) {
      // Status filter
      final matchesStatus = switch (_filter) {
        _StatusFilter.all => true,
        _StatusFilter.potential =>
          a.auditStatus == 'potential_false_cancellation',
        _StatusFilter.verifiedFalse =>
          a.auditStatus == 'verified_false_cancellation',
        _StatusFilter.verifiedValid =>
          a.auditStatus == 'verified_valid_cancellation',
        _StatusFilter.dismissed => a.auditStatus == 'dismissed',
      };

      if (!matchesStatus) return false;

      // Search filter
      if (_searchQuery.isEmpty) return true;

      final bookingStr = (a.bookingNumber ?? a.bookingId).toLowerCase();
      final customerStr = (a.customerName ?? '').toLowerCase();
      final phoneStr = (a.customerPhone ?? '').toLowerCase();
      final vendorStr = (a.vendorBusinessName ?? '').toLowerCase();
      final reasonStr = (a.cancellationReason ?? '').toLowerCase();

      return bookingStr.contains(_searchQuery) ||
          customerStr.contains(_searchQuery) ||
          phoneStr.contains(_searchQuery) ||
          vendorStr.contains(_searchQuery) ||
          reasonStr.contains(_searchQuery);
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
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.my_location_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'GPS Cancellation Audit',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Investigate potential false customer cancellations verified against vendor location tracking.',
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
                  tooltip: 'Refresh Audits',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Controls & Filters Bar (Responsive Wrap)
            auditsAsync.maybeWhen(
              data: (allAudits) {
                final potentialCount = allAudits
                    .where((a) => a.auditStatus == 'potential_false_cancellation')
                    .length;
                final verifiedFalseCount = allAudits
                    .where((a) => a.auditStatus == 'verified_false_cancellation')
                    .length;
                final verifiedValidCount = allAudits
                    .where((a) => a.auditStatus == 'verified_valid_cancellation')
                    .length;
                final dismissedCount =
                    allAudits.where((a) => a.auditStatus == 'dismissed').length;

                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Search Field
                    SizedBox(
                      width: 300,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search booking #, customer, vendor...',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 16),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),

                    // Filter Chips Scrollable Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All Audits',
                            count: allAudits.length,
                            selected: _filter == _StatusFilter.all,
                            onTap: () =>
                                setState(() => _filter = _StatusFilter.all),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Potential False',
                            count: potentialCount,
                            color: AppColors.warning,
                            selected: _filter == _StatusFilter.potential,
                            onTap: () => setState(
                                () => _filter = _StatusFilter.potential),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Verified False',
                            count: verifiedFalseCount,
                            color: AppColors.error,
                            selected: _filter == _StatusFilter.verifiedFalse,
                            onTap: () => setState(
                                () => _filter = _StatusFilter.verifiedFalse),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Verified Valid',
                            count: verifiedValidCount,
                            color: AppColors.success,
                            selected: _filter == _StatusFilter.verifiedValid,
                            onTap: () => setState(
                                () => _filter = _StatusFilter.verifiedValid),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Dismissed',
                            count: dismissedCount,
                            color: AppColors.textSecondary,
                            selected: _filter == _StatusFilter.dismissed,
                            onTap: () => setState(
                                () => _filter = _StatusFilter.dismissed),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // Table Content (Dual Scrollable + Responsive Constraints)
            Expanded(
              child: auditsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error loading GPS cancellation audits: $e',
                      style: const TextStyle(color: AppColors.error)),
                ),
                data: (allAudits) {
                  final filtered = _applyFilters(allAudits);

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.location_off_rounded,
                              size: 48, color: AppColors.border),
                          SizedBox(height: 12),
                          Text(
                            'No GPS cancellation audit records found',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    minWidth: constraints.maxWidth),
                                child: DataTable(
                                  columnSpacing: 24,
                                  headingRowColor: WidgetStateProperty.all(
                                      const Color(0xFFF7F8FA)),
                                  columns: const [
                                    DataColumn(label: Text('Booking Ref')),
                                    DataColumn(label: Text('Customer')),
                                    DataColumn(label: Text('Vendor')),
                                    DataColumn(label: Text('Reason')),
                                    DataColumn(
                                        label: Text('Distance / Geofence')),
                                    DataColumn(label: Text('Status')),
                                    DataColumn(label: Text('Audited At')),
                                    DataColumn(label: Text('Actions')),
                                  ],
                                  rows: filtered.map((audit) {
                                    final bookingRef = audit.bookingNumber !=
                                                null &&
                                            audit.bookingNumber!.isNotEmpty
                                        ? '#${audit.bookingNumber}'
                                        : '#${audit.bookingId.length > 8 ? audit.bookingId.substring(0, 8).toUpperCase() : audit.bookingId}';

                                    return DataRow(
                                      cells: [
                                        // Booking Ref
                                        DataCell(
                                          Text(
                                            bookingRef,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        // Customer
                                        DataCell(
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 160),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  audit.customerName ??
                                                      'Customer',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600),
                                                ),
                                                if (audit.customerPhone !=
                                                    null)
                                                  Text(
                                                    audit.customerPhone!,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          AppColors.textSecondary,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Vendor
                                        DataCell(
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 180),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  audit.vendorBusinessName ??
                                                      'Vendor',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600),
                                                ),
                                                if (audit.vendorPhone != null)
                                                  Text(
                                                    audit.vendorPhone!,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          AppColors.textSecondary,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Reason
                                        DataCell(
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                                maxWidth: 180),
                                            child: Text(
                                              audit.cancellationReason
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? audit.cancellationReason!
                                                  : 'Unspecified',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ),
                                        // Distance / Geofence
                                        DataCell(
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${audit.minDistanceMeters.toStringAsFixed(1)} m',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              Text(
                                                'Max: ${audit.geofenceRadiusMeters.toStringAsFixed(0)} m',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Status Badge
                                        DataCell(
                                          _StatusChip(status: audit.auditStatus),
                                        ),
                                        // Audited At
                                        DataCell(
                                          Text(
                                            _dateFmt.format(audit.auditedAt),
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        // Actions
                                        DataCell(
                                          OutlinedButton.icon(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) =>
                                                    GpsAuditDetailsDialog(
                                                        audit: audit),
                                              );
                                            },
                                            icon: const Icon(
                                                Icons.visibility_outlined,
                                                size: 14),
                                            label: const Text('View Evidence'),
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              textStyle: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? effectiveColor.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? effectiveColor : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? effectiveColor : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? effectiveColor.withValues(alpha: 0.2)
                    : AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? effectiveColor : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'verified_false_cancellation' => ('Verified False', AppColors.error),
      'verified_valid_cancellation' => ('Verified Valid', AppColors.success),
      'dismissed' => ('Dismissed', AppColors.textSecondary),
      'pending_review' => ('Pending Review', Colors.blue),
      _ => ('Potential False', AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
