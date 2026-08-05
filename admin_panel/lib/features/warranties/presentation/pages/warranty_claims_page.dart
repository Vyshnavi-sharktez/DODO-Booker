import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/service_warranty.dart';
import '../../application/warranties_providers.dart';
import '../widgets/warranty_claim_details_dialog.dart';
import '../widgets/warranty_claim_reject_dialog.dart';
import '../../../bookings/presentation/widgets/booking_details_dialog.dart';
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';

import 'package:go_router/go_router.dart';

class WarrantyClaimsPage extends ConsumerStatefulWidget {
  const WarrantyClaimsPage({super.key});

  @override
  ConsumerState<WarrantyClaimsPage> createState() => _WarrantyClaimsPageState();
}

class _WarrantyClaimsPageState extends ConsumerState<WarrantyClaimsPage> {
  String _searchQuery = '';
  String _selectedStatusFilter = 'All Claims';
  String? _selectedVendorFilter;
  DateTime? _selectedDateFilter;

  Future<void> _openBookingDetails(String bookingId) async {
    if (bookingId.isEmpty) return;
    try {
      final repo = ref.read(bookingsRepositoryProvider);
      final booking = await repo.fetchBookingById(bookingId);
      if (booking != null && mounted) {
        showDialog(
          context: context,
          builder: (_) => BookingDetailsDialog(booking: booking),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load booking details.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading booking: $e')),
        );
      }
    }
  }

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateFilter ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _selectedDateFilter = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warrantiesAsync = ref.watch(adminWarrantiesProvider);
    final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Title Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Service Warranty Claims & Operations',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Monitor warranty lifecycles, review evidence photos, track vendor rework progress, and manage resolutions.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => context.go('/dashboard/warranty-analytics'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.analytics_rounded, size: 16),
                      label: const Text('Warranty Analytics'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => ref.invalidate(adminWarrantiesProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Refresh Warranties',
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            warrantiesAsync.when(
              data: (warranties) {
                final totalClaims = warranties.length;
                final pendingClaims = warranties.where((w) => w.isClaimed).length;
                final inProgressClaims = warranties.where((w) => w.isReworkInProgress || w.isReworkAccepted).length;
                final resolvedClaims = warranties.where((w) => w.isResolved).length;
                final rejectedClaims = warranties.where((w) => w.isRejected).length;

                // Filter list
                final filtered = warranties.where((w) {
                  // Search query filter
                  if (_searchQuery.isNotEmpty) {
                    final q = _searchQuery.toLowerCase();
                    final cName = (w.customerName ?? '').toLowerCase();
                    final cEmail = (w.customerEmail ?? '').toLowerCase();
                    final cPhone = (w.customerPhone ?? '').toLowerCase();
                    final bNum = (w.bookingNumber ?? w.bookingId).toLowerCase();
                    final rNum = (w.reworkBookingNumber ?? w.reworkBookingId ?? '').toLowerCase();
                    final vName = (w.vendorName ?? w.reworkVendorName ?? '').toLowerCase();
                    final cert = w.certificateNumber.toLowerCase();

                    final matchesSearch = cName.contains(q) ||
                        cEmail.contains(q) ||
                        cPhone.contains(q) ||
                        bNum.contains(q) ||
                        rNum.contains(q) ||
                        vName.contains(q) ||
                        cert.contains(q);

                    if (!matchesSearch) return false;
                  }

                  // Status filter
                  switch (_selectedStatusFilter) {
                    case 'Pending Review':
                      if (!w.isClaimed) return false;
                      break;
                    case 'Approved':
                      if (!w.isApproved || w.isResolved) return false;
                      break;
                    case 'In Progress':
                      if (!w.isReworkInProgress && !w.isReworkAccepted) return false;
                      break;
                    case 'Resolved':
                      if (!w.isResolved) return false;
                      break;
                    case 'Rejected':
                      if (!w.isRejected) return false;
                      break;
                  }

                  // Vendor filter
                  if (_selectedVendorFilter != null && _selectedVendorFilter!.isNotEmpty) {
                    final vName = w.vendorName ?? w.reworkVendorName ?? '';
                    if (vName != _selectedVendorFilter) return false;
                  }

                  // Date filter
                  if (_selectedDateFilter != null) {
                    final cDate = w.claimedAt;
                    if (cDate == null) return false;
                    final sameDay = cDate.year == _selectedDateFilter!.year &&
                        cDate.month == _selectedDateFilter!.month &&
                        cDate.day == _selectedDateFilter!.day;
                    if (!sameDay) return false;
                  }

                  return true;
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Metrics Grid (5 Cards)
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            title: 'Total Claims',
                            value: '$totalClaims',
                            icon: Icons.shield_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            title: 'Pending Review',
                            value: '$pendingClaims',
                            icon: Icons.pending_actions_rounded,
                            color: const Color(0xFFDD6B20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            title: 'In Progress',
                            value: '$inProgressClaims',
                            icon: Icons.engineering_rounded,
                            color: const Color(0xFF3182CE),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            title: 'Resolved',
                            value: '$resolvedClaims',
                            icon: Icons.check_circle_rounded,
                            color: const Color(0xFF38A169),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _MetricCard(
                            title: 'Rejected',
                            value: '$rejectedClaims',
                            icon: Icons.cancel_rounded,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Filter & Search Controls
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              // Search Input
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  decoration: InputDecoration(
                                    hintText: 'Search customer, booking #, rework #, vendor, certificate...',
                                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: AppColors.border),
                                    ),
                                  ),
                                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Vendor Dropdown Filter
                              SizedBox(
                                width: 180,
                                child: DropdownButtonFormField<String?>(
                                  value: _selectedVendorFilter,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    hintText: 'Filter by Vendor',
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: null, child: Text('All Vendors')),
                                    ...vendors.map((v) => DropdownMenuItem(value: v.businessName, child: Text(v.businessName))),
                                  ],
                                  onChanged: (val) => setState(() => _selectedVendorFilter = val),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Date Range Filter Button
                              OutlinedButton.icon(
                                onPressed: _pickDateFilter,
                                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                                label: Text(
                                  _selectedDateFilter != null
                                      ? DateFormat('dd MMM yyyy').format(_selectedDateFilter!)
                                      : 'Filter Date',
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),

                              if (_selectedDateFilter != null || _selectedVendorFilter != null || _searchQuery.isNotEmpty || _selectedStatusFilter != 'All Claims') ...[
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () => setState(() {
                                    _searchQuery = '';
                                    _selectedStatusFilter = 'All Claims';
                                    _selectedVendorFilter = null;
                                    _selectedDateFilter = null;
                                  }),
                                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                                  label: const Text('Clear'),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Status Filter Chips
                          Row(
                            children: [
                              const Text('Status Filter: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    'All Claims',
                                    'Pending Review',
                                    'Approved',
                                    'In Progress',
                                    'Resolved',
                                    'Rejected',
                                  ].map((filter) {
                                    final isSelected = _selectedStatusFilter == filter;
                                    return ChoiceChip(
                                      label: Text(filter),
                                      selected: isSelected,
                                      selectedColor: AppColors.primary,
                                      labelStyle: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : AppColors.textPrimary,
                                      ),
                                      onSelected: (sel) {
                                        if (sel) setState(() => _selectedStatusFilter = filter);
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Claims Table Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Submitted Warranty Claims (${filtered.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          if (filtered.isEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(
                                child: Text(
                                  'No warranty claims found matching your filters.',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              ),
                            ),
                          ] else ...[
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                                columns: const [
                                  DataColumn(label: Text('Certificate / Ref', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Original Booking', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Rework Booking', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Vendor', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Status & Stage', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Claim Date', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                                ],
                                rows: filtered.map((warranty) {
                                  return _buildWarrantyRow(context, warranty);
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(60),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, st) => Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text('Error loading warranty claims: $err', style: const TextStyle(color: AppColors.error)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildWarrantyRow(BuildContext context, ServiceWarranty warranty) {
    final dateFmt = DateFormat('dd MMM yyyy');
    final bookingNum = warranty.bookingNumber ??
        (warranty.bookingId.length > 8
            ? warranty.bookingId.substring(0, 8).toUpperCase()
            : warranty.bookingId.toUpperCase());
    final reworkNum = warranty.reworkBookingNumber ??
        (warranty.reworkBookingId != null && warranty.reworkBookingId!.length > 8
            ? warranty.reworkBookingId!.substring(0, 8).toUpperCase()
            : warranty.reworkBookingId);

    final customerName = warranty.customerName?.isNotEmpty == true
        ? warranty.customerName!
        : 'Customer';
    final customerContact = warranty.customerEmail ?? warranty.customerPhone ?? '—';
    final vendorName = warranty.reworkVendorName ?? warranty.vendorName ?? 'Unassigned';

    return DataRow(
      cells: [
        // Certificate Number & Code
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                warranty.certificateNumber,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                'Issued ${dateFmt.format(warranty.issuedAt)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),

        // Customer Info
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customerName,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(
                customerContact,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),

        // Original Booking Quick Link
        DataCell(
          InkWell(
            onTap: () => _openBookingDetails(warranty.bookingId),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '#$bookingNum',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.open_in_new_rounded, size: 12, color: AppColors.primary),
              ],
            ),
          ),
        ),

        // Rework Booking Quick Link
        DataCell(
          reworkNum != null
              ? InkWell(
                  onTap: () => _openBookingDetails(warranty.reworkBookingId!),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#$reworkNum',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF38A169)),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.open_in_new_rounded, size: 12, color: Color(0xFF38A169)),
                    ],
                  ),
                )
              : const Text('—', style: TextStyle(color: AppColors.textSecondary)),
        ),

        // Vendor
        DataCell(
          Text(
            vendorName,
            style: const TextStyle(fontSize: 13),
          ),
        ),

        // Status Badge Chip
        DataCell(
          _StatusBadge(warranty: warranty),
        ),

        // Claim Date
        DataCell(
          Text(
            warranty.claimedAt != null ? dateFmt.format(warranty.claimedAt!) : '—',
            style: const TextStyle(fontSize: 12),
          ),
        ),

        // Actions
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.timeline_rounded, size: 20, color: AppColors.primary),
                tooltip: 'View Timeline & Real-Time Rework Progress',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => WarrantyClaimDetailsDialog(warranty: warranty),
                  );
                },
              ),

              if (warranty.isClaimed) ...[
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, size: 20, color: Color(0xFF38A169)),
                  tooltip: 'Approve Claim',
                  onPressed: () => _handleQuickApprove(warranty),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, size: 20, color: AppColors.error),
                  tooltip: 'Reject Claim',
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => WarrantyClaimRejectDialog(warranty: warranty),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleQuickApprove(ServiceWarranty warranty) async {
    final bookingNum = warranty.bookingNumber ?? warranty.bookingId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Warranty Claim?'),
        content: Text(
          'Approve claim for Booking #$bookingNum and move rework booking into dispatch workflow?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF38A169)),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final repo = ref.read(warrantiesRepositoryProvider);
      await repo.approveWarrantyClaim(
        warrantyId: warranty.id,
        reworkBookingId: warranty.reworkBookingId,
        customerId: warranty.customerId,
        bookingNumber: bookingNum,
      );

      ref.invalidate(adminWarrantiesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Warranty Claim for Booking #$bookingNum approved.'),
          backgroundColor: const Color(0xFF38A169),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to approve claim: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
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
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ServiceWarranty warranty;

  const _StatusBadge({required this.warranty});

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = _getBadgeConfig(warranty);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  (String, Color, Color) _getBadgeConfig(ServiceWarranty w) {
    if (w.isResolved) {
      return ('RESOLVED', const Color(0xFF2C7A7B), const Color(0xFFE6FFFA));
    }
    if (w.isRejected) {
      return ('REJECTED', const Color(0xFFC53030), const Color(0xFFFFF5F5));
    }
    if (w.isReworkInProgress) {
      return ('IN PROGRESS', const Color(0xFF6B46C1), const Color(0xFFF3E8FF));
    }
    if (w.isReworkAccepted) {
      return ('VENDOR ACCEPTED', const Color(0xFF3182CE), const Color(0xFFEBF8FF));
    }
    if (w.isApproved) {
      return ('APPROVED', const Color(0xFF276749), const Color(0xFFF0FFF4));
    }
    if (w.isClaimed) {
      return ('PENDING REVIEW', const Color(0xFFDD6B20), const Color(0xFFFFFAF0));
    }
    return (w.status.toUpperCase(), AppColors.textSecondary, Colors.grey.shade100);
  }
}
