import 'package:excel/excel.dart' as excel_pkg;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../../dispatch_analytics/application/csv_downloader.dart';
import '../../application/warranties_providers.dart';
import '../../domain/models/service_warranty.dart';
import '../widgets/warranty_claim_details_dialog.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _exportDateFmt = DateFormat('yyyyMMdd_HHmmss');

class WarrantyAnalyticsPage extends ConsumerStatefulWidget {
  const WarrantyAnalyticsPage({super.key});

  @override
  ConsumerState<WarrantyAnalyticsPage> createState() => _WarrantyAnalyticsPageState();
}

class _WarrantyAnalyticsPageState extends ConsumerState<WarrantyAnalyticsPage> {
  String _searchQuery = '';
  String _selectedDateRange = 'All Time'; // 'All Time', 'Today', 'Last 7 Days', 'Last 30 Days', 'Custom'
  DateTimeRange? _customDateRange;
  String _selectedStatusFilter = 'All'; // 'All', 'Active', 'Claimed', 'Approved', 'Resolved', 'Rejected', 'Expired'
  String _selectedVendorFilter = 'All';

  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _selectedDateRange = 'All Time';
      _customDateRange = null;
      _selectedStatusFilter = 'All';
      _selectedVendorFilter = 'All';
    });
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedDateRange = 'Custom';
      });
    }
  }

  bool _matchesDateRange(DateTime dt) {
    final now = DateTime.now();
    switch (_selectedDateRange) {
      case 'Today':
        return dt.year == now.year && dt.month == now.month && dt.day == now.day;
      case 'Last 7 Days':
        return dt.isAfter(now.subtract(const Duration(days: 7)));
      case 'Last 30 Days':
        return dt.isAfter(now.subtract(const Duration(days: 30)));
      case 'Custom':
        if (_customDateRange == null) return true;
        return dt.isAfter(_customDateRange!.start.subtract(const Duration(days: 1))) &&
            dt.isBefore(_customDateRange!.end.add(const Duration(days: 1)));
      case 'All Time':
      default:
        return true;
    }
  }

  String _escapeCsv(String? input) {
    if (input == null || input.isEmpty) return '';
    if (input.contains(',') || input.contains('"') || input.contains('\n')) {
      final escaped = input.replaceAll('"', '""');
      return '"$escaped"';
    }
    return input;
  }

  Future<void> _exportCsv(List<ServiceWarranty> records) async {
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No warranty records to export.')),
      );
      return;
    }

    final buf = StringBuffer();
    buf.writeln(
      'Certificate Number,Booking Number,Customer Name,Customer Email,Customer Phone,Vendor Name,Warranty Days,Issued Date,Expiry Date,Status,Claimed Date,Rework Booking Number,Rework Vendor,Resolution Date,Notes/Issue',
    );

    for (final w in records) {
      final cert = _escapeCsv(w.certificateNumber);
      final bNum = _escapeCsv(w.bookingNumber ?? w.bookingId);
      final cName = _escapeCsv(w.customerName);
      final cEmail = _escapeCsv(w.customerEmail);
      final cPhone = _escapeCsv(w.customerPhone);
      final vName = _escapeCsv(w.vendorName);
      final wDays = w.warrantyDays;
      final issued = _escapeCsv(_dateFmt.format(w.issuedAt));
      final expires = _escapeCsv(_dateFmt.format(w.expiresAt));
      final status = _escapeCsv(w.effectiveStatus);
      final claimed = _escapeCsv(w.claimedAt != null ? _dateFmt.format(w.claimedAt!) : '');
      final rNum = _escapeCsv(w.reworkBookingNumber ?? w.reworkBookingId);
      final rVendor = _escapeCsv(w.reworkVendorName);
      final resolved = _escapeCsv(w.reworkCompletedAt != null ? _dateFmt.format(w.reworkCompletedAt!) : '');
      final notes = _escapeCsv(w.issueDescription);

      buf.writeln(
        '$cert,$bNum,$cName,$cEmail,$cPhone,$vName,$wDays,$issued,$expires,$status,$claimed,$rNum,$rVendor,$resolved,$notes',
      );
    }

    final filename = 'warranty_analytics_report_${_exportDateFmt.format(DateTime.now())}.csv';
    await downloadCsv(buf.toString(), filename);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${records.length} records to $filename')),
      );
    }
  }

  Future<void> _exportExcel(List<ServiceWarranty> records) async {
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No warranty records to export.')),
      );
      return;
    }

    try {
      final excel = excel_pkg.Excel.createExcel();
      final sheet = excel['Warranty Analytics'];
      excel.setDefaultSheet('Warranty Analytics');

      final headers = [
        'Certificate Number',
        'Booking Number',
        'Customer Name',
        'Customer Email',
        'Customer Phone',
        'Vendor Name',
        'Warranty Days',
        'Issued Date',
        'Expiry Date',
        'Status',
        'Claimed Date',
        'Rework Booking Number',
        'Rework Vendor',
        'Resolution Date',
        'Notes / Issue Description',
      ];

      sheet.appendRow(headers.map((h) => excel_pkg.TextCellValue(h)).toList());

      for (final w in records) {
        final row = [
          excel_pkg.TextCellValue(w.certificateNumber),
          excel_pkg.TextCellValue(w.bookingNumber ?? w.bookingId),
          excel_pkg.TextCellValue(w.customerName ?? ''),
          excel_pkg.TextCellValue(w.customerEmail ?? ''),
          excel_pkg.TextCellValue(w.customerPhone ?? ''),
          excel_pkg.TextCellValue(w.vendorName ?? ''),
          excel_pkg.IntCellValue(w.warrantyDays),
          excel_pkg.TextCellValue(_dateFmt.format(w.issuedAt)),
          excel_pkg.TextCellValue(_dateFmt.format(w.expiresAt)),
          excel_pkg.TextCellValue(w.effectiveStatus),
          excel_pkg.TextCellValue(w.claimedAt != null ? _dateFmt.format(w.claimedAt!) : ''),
          excel_pkg.TextCellValue(w.reworkBookingNumber ?? w.reworkBookingId ?? ''),
          excel_pkg.TextCellValue(w.reworkVendorName ?? ''),
          excel_pkg.TextCellValue(w.reworkCompletedAt != null ? _dateFmt.format(w.reworkCompletedAt!) : ''),
          excel_pkg.TextCellValue(w.issueDescription ?? ''),
        ];
        sheet.appendRow(row);
      }

      final bytes = excel.encode();
      if (bytes != null) {
        final csvFallback = StringBuffer();
        csvFallback.writeln(headers.join(','));
        for (final w in records) {
          csvFallback.writeln(
            '${_escapeCsv(w.certificateNumber)},${_escapeCsv(w.bookingNumber ?? w.bookingId)},${_escapeCsv(w.customerName)},${_escapeCsv(w.customerEmail)},${_escapeCsv(w.customerPhone)},${_escapeCsv(w.vendorName)},${w.warrantyDays},${_escapeCsv(_dateFmt.format(w.issuedAt))},${_escapeCsv(_dateFmt.format(w.expiresAt))},${_escapeCsv(w.effectiveStatus)},${_escapeCsv(w.claimedAt != null ? _dateFmt.format(w.claimedAt!) : '')},${_escapeCsv(w.reworkBookingNumber)},${_escapeCsv(w.reworkVendorName)},${_escapeCsv(w.reworkCompletedAt != null ? _dateFmt.format(w.reworkCompletedAt!) : '')},${_escapeCsv(w.issueDescription)}',
          );
        }

        final filename = 'warranty_analytics_${_exportDateFmt.format(DateTime.now())}.csv';
        await downloadCsv(csvFallback.toString(), filename);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully exported ${records.length} records to $filename')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel export error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final warrantiesAsync = ref.watch(adminAnalyticsWarrantiesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 16,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Warranty Analytics & Reports',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Track warranty certificates, claim trends, vendor rework performance, and resolution metrics.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                warrantiesAsync.maybeWhen(
                  data: (warranties) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _exportCsv(warranties),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Export CSV'),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _exportExcel(warranties),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.description_rounded, size: 16),
                        label: const Text('Export Excel'),
                      ),
                      IconButton(
                        onPressed: () => ref.invalidate(adminAnalyticsWarrantiesProvider),
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Refresh Data',
                      ),
                    ],
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),

            const SizedBox(height: 20),

            warrantiesAsync.when(
              data: (allWarranties) {
                // Apply Filters
                final filtered = allWarranties.where((w) {
                  // Date range filter
                  if (!_matchesDateRange(w.issuedAt) && !(w.claimedAt != null && _matchesDateRange(w.claimedAt!))) {
                    return false;
                  }

                  // Status filter
                  if (_selectedStatusFilter != 'All') {
                    if (w.effectiveStatus.toLowerCase() != _selectedStatusFilter.toLowerCase()) {
                      return false;
                    }
                  }

                  // Vendor filter
                  if (_selectedVendorFilter != 'All') {
                    final vName = (w.vendorName ?? w.reworkVendorName ?? '').toLowerCase();
                    if (vName != _selectedVendorFilter.toLowerCase()) {
                      return false;
                    }
                  }

                  // Search query filter
                  if (_searchQuery.isNotEmpty) {
                    final q = _searchQuery.toLowerCase();
                    final cert = w.certificateNumber.toLowerCase();
                    final bNum = (w.bookingNumber ?? w.bookingId).toLowerCase();
                    final cName = (w.customerName ?? '').toLowerCase();
                    final vName = (w.vendorName ?? w.reworkVendorName ?? '').toLowerCase();
                    final desc = (w.issueDescription ?? '').toLowerCase();

                    final match = cert.contains(q) ||
                        bNum.contains(q) ||
                        cName.contains(q) ||
                        vName.contains(q) ||
                        desc.contains(q);
                    if (!match) return false;
                  }

                  return true;
                }).toList();

                // Compute KPI Metrics
                final totalIssued = filtered.length;
                final activeCount = filtered.where((w) => w.isActive).length;
                final claimsSubmitted = filtered.where((w) => w.claimedAt != null || w.isClaimed || w.isApproved || w.isResolved || w.isRejected).length;
                final claimsApproved = filtered.where((w) => w.isApproved || w.isReworkAccepted || w.isReworkInProgress || w.isReworkCompleted || w.isResolved).length;
                final claimsRejected = filtered.where((w) => w.isRejected).length;
                final claimsResolved = filtered.where((w) => w.isResolved).length;
                final expiredCount = filtered.where((w) => w.isExpired).length;

                // Average Resolution Time Calculation (in hours)
                final resolvedWithTimes = filtered.where((w) => w.isResolved && w.claimedAt != null).toList();
                double avgResolutionHours = 0.0;
                if (resolvedWithTimes.isNotEmpty) {
                  double totalHours = 0.0;
                  for (final r in resolvedWithTimes) {
                    final endDt = r.reworkCompletedAt ?? r.updatedAt;
                    final diff = endDt.difference(r.claimedAt!).inMinutes / 60.0;
                    if (diff > 0) totalHours += diff;
                  }
                  avgResolutionHours = totalHours / resolvedWithTimes.length;
                }

                final avgResDisplay = avgResolutionHours > 0
                    ? (avgResolutionHours >= 24
                        ? '${(avgResolutionHours / 24).toStringAsFixed(1)} days'
                        : '${avgResolutionHours.toStringAsFixed(1)} hrs')
                    : 'N/A';

                // Extract unique vendor names for filter
                final uniqueVendors = <String>{'All'};
                for (final w in allWarranties) {
                  if (w.vendorName != null && w.vendorName!.isNotEmpty) {
                    uniqueVendors.add(w.vendorName!);
                  }
                  if (w.reworkVendorName != null && w.reworkVendorName!.isNotEmpty) {
                    uniqueVendors.add(w.reworkVendorName!);
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Filters Card
                    _FiltersCard(
                      onSearchChanged: (v) => setState(() => _searchQuery = v),
                      selectedDateRange: _selectedDateRange,
                      onDateRangeChanged: (v) {
                        if (v == 'Custom') {
                          _pickCustomDateRange();
                        } else {
                          setState(() {
                            _selectedDateRange = v;
                            _customDateRange = null;
                          });
                        }
                      },
                      selectedStatus: _selectedStatusFilter,
                      onStatusChanged: (v) => setState(() => _selectedStatusFilter = v),
                      selectedVendor: _selectedVendorFilter,
                      vendorsList: uniqueVendors.toList(),
                      onVendorChanged: (v) => setState(() => _selectedVendorFilter = v),
                      onReset: _resetFilters,
                    ),

                    const SizedBox(height: 24),

                    // 8 KPI Cards Grid
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final crossAxisCount = width > 1200
                            ? 4
                            : (width > 800 ? 3 : (width > 500 ? 2 : 1));

                        return GridView.count(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: width > 1200 ? 2.3 : 2.0,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _KpiCard(
                              title: 'Total Warranties',
                              value: '$totalIssued',
                              subtitle: 'Issued certificates',
                              icon: Icons.shield_rounded,
                              color: const Color(0xFF3182CE),
                            ),
                            _KpiCard(
                              title: 'Active Coverage',
                              value: '$activeCount',
                              subtitle: '${totalIssued > 0 ? (activeCount / totalIssued * 100).toStringAsFixed(1) : 0}% of total',
                              icon: Icons.verified_user_rounded,
                              color: const Color(0xFF38A169),
                            ),
                            _KpiCard(
                              title: 'Claims Submitted',
                              value: '$claimsSubmitted',
                              subtitle: '${totalIssued > 0 ? (claimsSubmitted / totalIssued * 100).toStringAsFixed(1) : 0}% claim rate',
                              icon: Icons.rate_review_rounded,
                              color: const Color(0xFF805AD5),
                            ),
                            _KpiCard(
                              title: 'Claims Approved',
                              value: '$claimsApproved',
                              subtitle: 'Rework authorized',
                              icon: Icons.thumb_up_alt_rounded,
                              color: const Color(0xFF00A3C4),
                            ),
                            _KpiCard(
                              title: 'Claims Rejected',
                              value: '$claimsRejected',
                              subtitle: '${claimsSubmitted > 0 ? (claimsRejected / claimsSubmitted * 100).toStringAsFixed(1) : 0}% rejection rate',
                              icon: Icons.cancel_rounded,
                              color: const Color(0xFFE53E3E),
                            ),
                            _KpiCard(
                              title: 'Claims Resolved',
                              value: '$claimsResolved',
                              subtitle: '${claimsSubmitted > 0 ? (claimsResolved / claimsSubmitted * 100).toStringAsFixed(1) : 0}% resolution rate',
                              icon: Icons.task_alt_rounded,
                              color: const Color(0xFF276749),
                            ),
                            _KpiCard(
                              title: 'Expired Warranties',
                              value: '$expiredCount',
                              subtitle: 'Coverage elapsed',
                              icon: Icons.history_rounded,
                              color: const Color(0xFF718096),
                            ),
                            _KpiCard(
                              title: 'Avg Resolution Time',
                              value: avgResDisplay,
                              subtitle: 'Claim to completion',
                              icon: Icons.timer_rounded,
                              color: const Color(0xFFD69E2E),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 28),

                    // Analytics Charts & Visual Breakdowns Section
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column: Monthly Trends & Top Vendors
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              _MonthlyTrendsCard(warranties: filtered),
                              const SizedBox(height: 24),
                              _TopVendorsReworkCard(warranties: filtered),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Right Column: Status Distribution & Issue Categories
                        Expanded(
                          flex: 2,
                          child: Column(
                            children: [
                              _StatusDistributionCard(
                                total: totalIssued,
                                active: activeCount,
                                claims: claimsSubmitted,
                                approved: claimsApproved,
                                resolved: claimsResolved,
                                rejected: claimsRejected,
                                expired: expiredCount,
                              ),
                              const SizedBox(height: 24),
                              _TopIssuesCard(warranties: filtered),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Detailed Warranties Data Table
                    _WarrantiesDataTable(
                      warranties: filtered,
                      onViewDetails: (w) {
                        showDialog(
                          context: context,
                          builder: (_) => WarrantyClaimDetailsDialog(warranty: w),
                        );
                      },
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 400,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text('Error loading warranty analytics: $err'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(adminAnalyticsWarrantiesProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filters Card Widget ───────────────────────────────────────────────────────

class _FiltersCard extends StatelessWidget {
  final ValueChanged<String> onSearchChanged;
  final String selectedDateRange;
  final ValueChanged<String> onDateRangeChanged;
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;
  final String selectedVendor;
  final List<String> vendorsList;
  final ValueChanged<String> onVendorChanged;
  final VoidCallback onReset;

  const _FiltersCard({
    required this.onSearchChanged,
    required this.selectedDateRange,
    required this.onDateRangeChanged,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.selectedVendor,
    required this.vendorsList,
    required this.onVendorChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AdminSearchBar(
            width: 320,
            hintText: 'Search by Cert #, Booking #, Customer, or Vendor...',
            onChanged: onSearchChanged,
          ),
          // Date Range Dropdown
          DropdownButton<String>(
            value: selectedDateRange,
            underline: const SizedBox.shrink(),
            items: ['All Time', 'Today', 'Last 7 Days', 'Last 30 Days', 'Custom']
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (val) {
              if (val != null) onDateRangeChanged(val);
            },
          ),
          // Status Dropdown
          DropdownButton<String>(
            value: selectedStatus,
            underline: const SizedBox.shrink(),
            items: ['All', 'Active', 'Claimed', 'Approved', 'Resolved', 'Rejected', 'Expired']
                .map((s) => DropdownMenuItem(value: s, child: Text('Status: $s')))
                .toList(),
            onChanged: (val) {
              if (val != null) onStatusChanged(val);
            },
          ),
          // Vendor Dropdown
          DropdownButton<String>(
            value: vendorsList.contains(selectedVendor) ? selectedVendor : 'All',
            underline: const SizedBox.shrink(),
            items: vendorsList
                .map((v) => DropdownMenuItem(value: v, child: Text('Vendor: $v')))
                .toList(),
            onChanged: (val) {
              if (val != null) onVendorChanged(val);
            },
          ),
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.clear_all_rounded, size: 16),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// ── KPI Card Widget ────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
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

// ── Monthly Trends Breakdown Card ─────────────────────────────────────────────

class _MonthlyTrendsCard extends StatelessWidget {
  final List<ServiceWarranty> warranties;

  const _MonthlyTrendsCard({required this.warranties});

  @override
  Widget build(BuildContext context) {
    // Group by month label e.g. "Jan 2026"
    final monthMap = <String, Map<String, int>>{};

    for (final w in warranties) {
      final key = DateFormat('MMM yyyy').format(w.issuedAt);
      monthMap.putIfAbsent(key, () => {'issued': 0, 'claimed': 0, 'resolved': 0});
      monthMap[key]!['issued'] = (monthMap[key]!['issued'] ?? 0) + 1;

      if (w.claimedAt != null || w.isClaimed || w.isApproved || w.isResolved) {
        final claimKey = w.claimedAt != null ? DateFormat('MMM yyyy').format(w.claimedAt!) : key;
        monthMap.putIfAbsent(claimKey, () => {'issued': 0, 'claimed': 0, 'resolved': 0});
        monthMap[claimKey]!['claimed'] = (monthMap[claimKey]!['claimed'] ?? 0) + 1;
      }

      if (w.isResolved) {
        final resDt = w.reworkCompletedAt ?? w.updatedAt;
        final resKey = DateFormat('MMM yyyy').format(resDt);
        monthMap.putIfAbsent(resKey, () => {'issued': 0, 'claimed': 0, 'resolved': 0});
        monthMap[resKey]!['resolved'] = (monthMap[resKey]!['resolved'] ?? 0) + 1;
      }
    }

    final entries = monthMap.entries.toList();
    if (entries.isEmpty) {
      return _buildContainer(
        title: 'Monthly Issuance & Claim Trends',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No trend data available for selected filters.', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      );
    }

    int maxVal = 1;
    for (final e in entries) {
      final m = e.value;
      if ((m['issued'] ?? 0) > maxVal) maxVal = m['issued']!;
      if ((m['claimed'] ?? 0) > maxVal) maxVal = m['claimed']!;
      if ((m['resolved'] ?? 0) > maxVal) maxVal = m['resolved']!;
    }

    return _buildContainer(
      title: 'Monthly Warranty & Claim Trends',
      child: Column(
        children: entries.map((e) {
          final month = e.key;
          final issued = e.value['issued'] ?? 0;
          final claimed = e.value['claimed'] ?? 0;
          final resolved = e.value['resolved'] ?? 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(month, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                    Text('Issued: $issued  |  Claimed: $claimed  |  Resolved: $resolved', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 6),
                _ProgressBar(label: 'Issued', value: issued, max: maxVal, color: const Color(0xFF3182CE)),
                const SizedBox(height: 4),
                _ProgressBar(label: 'Claimed', value: claimed, max: maxVal, color: const Color(0xFF805AD5)),
                const SizedBox(height: 4),
                _ProgressBar(label: 'Resolved', value: resolved, max: maxVal, color: const Color(0xFF38A169)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContainer({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;

  const _ProgressBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text('$value', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ),
      ],
    );
  }
}

// ── Top Vendors Rework Performance Card ───────────────────────────────────────

class _TopVendorsReworkCard extends StatelessWidget {
  final List<ServiceWarranty> warranties;

  const _TopVendorsReworkCard({required this.warranties});

  @override
  Widget build(BuildContext context) {
    final vendorStats = <String, Map<String, int>>{};

    for (final w in warranties) {
      final vName = w.reworkVendorName ?? w.vendorName;
      if (vName == null || vName.isEmpty) continue;

      vendorStats.putIfAbsent(vName, () => {'total': 0, 'completed': 0, 'rejected': 0});
      vendorStats[vName]!['total'] = (vendorStats[vName]!['total'] ?? 0) + 1;

      if (w.isResolved || w.isReworkCompleted) {
        vendorStats[vName]!['completed'] = (vendorStats[vName]!['completed'] ?? 0) + 1;
      } else if (w.isRejected) {
        vendorStats[vName]!['rejected'] = (vendorStats[vName]!['rejected'] ?? 0) + 1;
      }
    }

    final sortedVendors = vendorStats.entries.toList()
      ..sort((a, b) => (b.value['total'] ?? 0).compareTo(a.value['total'] ?? 0));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top Vendors Handling Reworks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          if (sortedVendors.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No vendor rework data found.', style: TextStyle(color: AppColors.textSecondary))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sortedVendors.take(5).length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, idx) {
                final entry = sortedVendors[idx];
                final name = entry.key;
                final total = entry.value['total'] ?? 0;
                final completed = entry.value['completed'] ?? 0;
                final pct = total > 0 ? (completed / total * 100).toStringAsFixed(0) : '0';

                return Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text('${idx + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                          Text('$completed completed / $total assigned rework jobs', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38A169).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('$pct% Success', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38A169))),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Status Distribution Card ──────────────────────────────────────────────────

class _StatusDistributionCard extends StatelessWidget {
  final int total;
  final int active;
  final int claims;
  final int approved;
  final int resolved;
  final int rejected;
  final int expired;

  const _StatusDistributionCard({
    required this.total,
    required this.active,
    required this.claims,
    required this.approved,
    required this.resolved,
    required this.rejected,
    required this.expired,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Status Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          _StatusRow(label: 'Active Coverage', count: active, total: total, color: const Color(0xFF38A169)),
          const SizedBox(height: 10),
          _StatusRow(label: 'Under Review / Claimed', count: claims, total: total, color: const Color(0xFF805AD5)),
          const SizedBox(height: 10),
          _StatusRow(label: 'Approved & Rework In Progress', count: approved, total: total, color: const Color(0xFF3182CE)),
          const SizedBox(height: 10),
          _StatusRow(label: 'Resolved & Completed', count: resolved, total: total, color: const Color(0xFF276749)),
          const SizedBox(height: 10),
          _StatusRow(label: 'Rejected', count: rejected, total: total, color: const Color(0xFFE53E3E)),
          const SizedBox(height: 10),
          _StatusRow(label: 'Expired', count: expired, total: total, color: const Color(0xFF718096)),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _StatusRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '0';
    final factor = total > 0 ? (count / total).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text('$count ($pct%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 4),
        Stack(
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
            ),
            FractionallySizedBox(
              widthFactor: factor,
              child: Container(
                height: 6,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Top Issue Descriptions Card ───────────────────────────────────────────────

class _TopIssuesCard extends StatelessWidget {
  final List<ServiceWarranty> warranties;

  const _TopIssuesCard({required this.warranties});

  @override
  Widget build(BuildContext context) {
    final issueCounts = <String, int>{};

    for (final w in warranties) {
      final desc = w.issueDescription ?? '';
      if (desc.isEmpty || desc == 'No detailed description provided.') continue;
      issueCounts[desc] = (issueCounts[desc] ?? 0) + 1;
    }

    final topIssues = issueCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top Warranty Claims & Issues', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          if (topIssues.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No detailed claim issue records found.', style: TextStyle(color: AppColors.textSecondary))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: topIssues.take(4).length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, idx) {
                final issue = topIssues[idx];
                return Row(
                  children: [
                    Icon(Icons.report_problem_outlined, size: 16, color: AppColors.error.withValues(alpha: 0.7)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue.key,
                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${issue.value} claims',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.error),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Detailed Data Table Widget ────────────────────────────────────────────────

class _WarrantiesDataTable extends StatelessWidget {
  final List<ServiceWarranty> warranties;
  final ValueChanged<ServiceWarranty> onViewDetails;

  const _WarrantiesDataTable({
    required this.warranties,
    required this.onViewDetails,
  });

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF38A169);
      case 'claimed':
      case 'under review':
        return const Color(0xFF805AD5);
      case 'approved':
      case 'vendor accepted':
        return const Color(0xFF3182CE);
      case 'in progress':
        return const Color(0xFFD69E2E);
      case 'resolved':
        return const Color(0xFF276749);
      case 'rejected':
        return const Color(0xFFE53E3E);
      case 'expired':
      default:
        return const Color(0xFF718096);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Warranty Records (${warranties.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const Text(
                  'Showing all matching filter results',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (warranties.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text('No warranty records match your filter criteria.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.background),
                columns: const [
                  DataColumn(label: Text('Certificate #', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Booking #', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Assigned Vendor', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Issued Date', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Expiry Date', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: warranties.map((w) {
                  final statusColor = _getStatusColor(w.effectiveStatus);
                  final bNum = (w.bookingNumber != null && w.bookingNumber!.isNotEmpty)
                      ? w.bookingNumber!
                      : w.bookingId.substring(0, 8);
                  final cName = w.customerName ?? 'Customer';
                  final vName = w.reworkVendorName ?? w.vendorName ?? 'Unassigned';

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          w.certificateNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                      DataCell(Text('#$bNum')),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(cName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (w.customerPhone != null)
                              Text(w.customerPhone!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      DataCell(Text(vName)),
                      DataCell(Text(_dateFmt.format(w.issuedAt))),
                      DataCell(Text(_dateFmt.format(w.expiresAt))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            w.effectiveStatus.toUpperCase(),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                          ),
                        ),
                      ),
                      DataCell(
                        TextButton(
                          onPressed: () => onViewDetails(w),
                          child: const Text('View Details'),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
