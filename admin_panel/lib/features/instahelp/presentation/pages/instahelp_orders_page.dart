import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/admin_search_bar.dart';
import '../../../../core/widgets/highlighted_text.dart';
import '../../../../core/widgets/pagination_bar.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../../notifications/application/providers/notifications_providers.dart';
import '../../../vendor_assignment/application/providers/vendor_assignment_providers.dart';
import '../../../vendor_assignment/domain/models/assignment_entry.dart';
import '../../../vendor_assignment/presentation/widgets/assignment_history_dialog.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../../bookings/application/invoice_service.dart';
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../bookings/domain/models/booking.dart';
import '../../../bookings/presentation/widgets/booking_details_dialog.dart';
import '../../../bookings/presentation/widgets/booking_assignment_dialog.dart';
import '../../../bookings/presentation/widgets/booking_edit_dialog.dart';
import '../../application/providers/instahelp_providers.dart';
import '../../domain/models/instahelp_order.dart';
import '../widgets/create_instahelp_booking_dialog.dart';

// ── Column widths ─────────────────────────────────────────────────────────────

const double _wId = 100;
const double _wCustomer = 140;
const double _wAssigned = 110;
const double _wDuration = 140;
const double _wDate = 95;
const double _wSlotTime = 110;
const double _wStatus = 110;
const double _wTotal = 90;
const double _wRating = 95;
const double _tableMinWidth =
    _wId + _wCustomer + _wAssigned + _wDuration + _wDate + _wSlotTime +
    _wStatus + _wTotal + _wRating + 240 + 32;

// ── Status config ─────────────────────────────────────────────────────────────

const _statusConfig = <String, (String, Color, Color)>{
  'pending':                ('Pending',                        Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'waiting_for_acceptance': ('Waiting for Vendor Acceptance', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'assigned':               ('Assigned',                       Color(0xFF3182CE), Color(0xFFEBF8FF)),
  'assigned_to_dodo_team':  ('DODO Assigned',                  Color(0xFF6B46C1), Color(0xFFF3E8FF)),
  'no_vendor_accepted':     ('No Vendor Accepted',             Color(0xFFE53E3E), Color(0xFFFFF5F5)),
  'accepted':               ('Accepted',                       Color(0xFF0369A1), Color(0xFFE0F2FE)),
  'on_the_way':             ('On The Way',                     Color(0xFF4A6FA5), Color(0xFFEBF4FF)),
  'arrived':                ('Arrived',                        Color(0xFF6B46C1), Color(0xFFF3E8FF)),
  'in_progress':            ('In Progress',                    Color(0xFF805AD5), Color(0xFFFAF5FF)),
  'completed':              ('Completed',                      Color(0xFF38A169), Color(0xFFF0FFF4)),
  'rejected':               ('Rejected',                       Color(0xFFC05621), Color(0xFFFEEBC8)),
  'cancelled':              ('Cancelled',                      Color(0xFFE53E3E), Color(0xFFFFF5F5)),
  'payment_failed':         ('Payment Failed',                 Color(0xFFE53E3E), Color(0xFFFFF5F5)),
};

const _allStatuses = [
  'pending', 'waiting_for_acceptance', 'assigned', 'assigned_to_dodo_team',
  'no_vendor_accepted', 'accepted', 'on_the_way', 'arrived', 'in_progress',
  'completed', 'rejected', 'cancelled', 'payment_failed',
];

const _cancellableStatuses = {
  'pending', 'assigned', 'assigned_to_dodo_team', 'accepted',
  'on_the_way', 'arrived', 'in_progress',
};

const _assignableStatuses = {
  'pending', 'assigned', 'assigned_to_dodo_team', 'rejected',
};

const String _kUnassigned = '__unassigned__';

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('dd MMM yyyy');
final _weekdayFmt = DateFormat('EEE');

// ── Page ──────────────────────────────────────────────────────────────────────

class InstaHelpOrdersPage extends ConsumerStatefulWidget {
  const InstaHelpOrdersPage({super.key});

  @override
  ConsumerState<InstaHelpOrdersPage> createState() =>
      _InstaHelpOrdersPageState();
}

class _InstaHelpOrdersPageState extends ConsumerState<InstaHelpOrdersPage> {
  String? _modeFilter; // null = All, 'scheduled', 'instant'
  String _searchQuery = '';
  String? _statusFilter;
  String? _assignedToFilter;
  DateTime? _dateFilter;
  DateTime? _createdDateFilter;
  int _page = 1;
  static const int _pageSize = 10;

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _vendorName(String vendorId) {
    if (vendorId.isEmpty) return '';
    final vendors = ref.read(vendorsNotifierProvider).valueOrNull ?? [];
    final match = vendors.where((v) => v.id == vendorId);
    if (match.isEmpty) return 'Unknown Vendor';
    return match.first.businessName;
  }

  // ── Filters ──────────────────────────────────────────────────────────────────

  List<InstaHelpOrder> _applyFilters(List<InstaHelpOrder> all) {
    var result = all;
    if (_modeFilter != null) {
      result = result.where((o) => o.modeType == _modeFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((o) =>
              o.booking.bookingNumber.toLowerCase().contains(q) ||
              (o.booking.customerName?.toLowerCase().contains(q) ?? false) ||
              (o.booking.customerPhone?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (_statusFilter != null) {
      if (_statusFilter == 'waiting_for_acceptance') {
        result = result
            .where((o) =>
                o.booking.dispatchStatus == 'dispatching' ||
                (o.booking.status == 'assigned' &&
                    o.booking.dispatchStatus != 'accepted'))
            .toList();
      } else if (_statusFilter == 'no_vendor_accepted') {
        result = result
            .where((o) => o.booking.dispatchStatus == 'exhausted')
            .toList();
      } else if (_statusFilter == 'assigned') {
        result = result
            .where((o) =>
                (o.booking.status == 'assigned' &&
                    o.booking.dispatchStatus == 'accepted') ||
                o.booking.status == 'accepted')
            .toList();
      } else if (_statusFilter == 'payment_failed') {
        result = result
            .where((o) =>
                o.booking.status == 'cancelled' &&
                o.booking.paymentStatus == 'failed')
            .toList();
      } else {
        result = result
            .where((o) => o.booking.status == _statusFilter)
            .toList();
      }
    }
    if (_assignedToFilter == _kUnassigned) {
      result = result.where((o) => o.booking.isUnassigned).toList();
    } else if (_assignedToFilter != null) {
      result = result
          .where((o) => o.booking.vendorId == _assignedToFilter)
          .toList();
    }
    if (_dateFilter != null) {
      result = result.where((o) {
        if (o.booking.serviceDate == null) return false;
        final d = o.booking.serviceDate!;
        return d.year == _dateFilter!.year &&
            d.month == _dateFilter!.month &&
            d.day == _dateFilter!.day;
      }).toList();
    }
    if (_createdDateFilter != null) {
      result = result.where((o) {
        if (o.booking.createdAt == null) return false;
        final d = o.booking.createdAt!.toLocal();
        return d.year == _createdDateFilter!.year &&
            d.month == _createdDateFilter!.month &&
            d.day == _createdDateFilter!.day;
      }).toList();
    }
    return result;
  }

  bool get _hasFilters =>
      _statusFilter != null ||
      _assignedToFilter != null ||
      _dateFilter != null ||
      _createdDateFilter != null;

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() { _dateFilter = picked; _page = 1; });
  }

  Future<void> _pickCreatedDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _createdDateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() { _createdDateFilter = picked; _page = 1; });
  }

  // ── Sync after mutations ──────────────────────────────────────────────────────

  Future<void> _syncOrders() async {
    await ref.read(instaHelpOrdersNotifierProvider.notifier).refresh();
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  void _openDetails(Booking booking) {
    showDialog(
      context: context,
      builder: (_) => BookingDetailsDialog(
        booking: booking,
        onAssign: _assignableStatuses.contains(booking.status)
            ? () => _openAssignDialog(booking)
            : null,
        allowAssign: _assignableStatuses.contains(booking.status),
      ),
    );
  }

  void _openEditDialog(Booking booking) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingEditDialog(
        booking: booking,
        onAssignRequested: _assignableStatuses.contains(booking.status)
            ? () => _openAssignDialog(booking)
            : null,
      ),
    );
  }

  void _openAssignDialog(Booking booking) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingAssignmentDialog(
        booking: booking,
        onSave: ({
          required assignmentType,
          vendorId,
          dodoTeamId,
          required serviceDate,
          notes,
        }) async {
          final assigneeName = switch (assignmentType) {
            'External Vendor' => _vendorName(vendorId ?? ''),
            'DODO Team' => 'DODO Team',
            _ => 'Unassigned',
          };
          final previousVendorId =
              booking.vendorId.isNotEmpty ? booking.vendorId : null;
          final previousVendorName =
              previousVendorId != null ? _vendorName(previousVendorId) : '';
          final isFirstAssignment = booking.isUnassigned;
          final adminUser = ref.read(currentAdminUserProvider);

          await ref
              .read(bookingsNotifierProvider.notifier)
              .updateBookingAssignment(
                booking.id,
                assignmentType: assignmentType,
                vendorId: vendorId,
                dodoTeamId: dodoTeamId,
                serviceDate: serviceDate,
                notes: notes,
              );

          if (assignmentType == 'External Vendor' &&
              (vendorId?.isNotEmpty ?? false)) {
            try {
              await ref
                  .read(notificationsNotifierProvider.notifier)
                  .createNotification(
                    userType: 'vendor',
                    userId: vendorId!,
                    title: 'New InstaHelp Booking Assigned',
                    message:
                        'You have been assigned InstaHelp booking #${booking.bookingNumber}.',
                    notificationType: isFirstAssignment
                        ? 'vendor_assigned'
                        : 'vendor_reassigned',
                    entityType: 'booking',
                    entityId: booking.id,
                  );
            } catch (_) {}
          }

          if (assignmentType != 'Unassigned') {
            try {
              await ref
                  .read(notificationsNotifierProvider.notifier)
                  .createNotification(
                    userType: 'customer',
                    userId: booking.customerId,
                    title: isFirstAssignment
                        ? 'Provider Assigned'
                        : 'Provider Reassigned',
                    message: isFirstAssignment
                        ? 'A service provider has been assigned to your InstaHelp booking.'
                        : 'A new service provider has been assigned to your InstaHelp booking.',
                    notificationType: isFirstAssignment
                        ? 'vendor_assigned'
                        : 'vendor_reassigned',
                    entityType: 'booking',
                    entityId: booking.id,
                  );
            } catch (_) {}
          }

          ref.read(vendorAssignmentHistoryProvider.notifier).addEntry(
                AssignmentEntry(
                  bookingId: booking.id,
                  bookingNumber: booking.bookingNumber,
                  previousVendorId: previousVendorId,
                  previousVendorName: previousVendorName,
                  newVendorId: vendorId ?? '',
                  newVendorName: assigneeName,
                  assignedAt: DateTime.now(),
                  adminName: adminUser?.displayName ?? 'Admin',
                ),
              );

          await _syncOrders();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  assignmentType == 'Unassigned'
                      ? 'Booking #${booking.bookingNumber} unassigned'
                      : isFirstAssignment
                          ? 'Booking #${booking.bookingNumber} assigned to $assigneeName'
                          : 'Booking #${booking.bookingNumber} reassigned to $assigneeName',
                ),
                backgroundColor: AppColors.success,
              ),
            );
          }
        },
      ),
    );
  }

  void _openHistoryDialog(Booking booking) {
    showDialog(
      context: context,
      builder: (_) => AssignmentHistoryDialog(booking: booking),
    );
  }

  Future<void> _startDodoService(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Start Service'),
        content: Text(
          'Start service for booking "${booking.bookingNumber}"?\n\n'
          'The DODO Team will be notified that the service is now in progress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Start Service'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(bookingsNotifierProvider.notifier)
          .startDodoTeamService(booking.id);
      try {
        await ref
            .read(notificationsNotifierProvider.notifier)
            .createNotification(
              userType: 'customer',
              userId: booking.customerId,
              title: 'Service Started',
              message: 'Your InstaHelp service is now in progress by the DODO Team.',
              notificationType: 'vendor_started',
              entityType: 'booking',
              entityId: booking.id,
            );
      } catch (_) {}
      await _syncOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Service started for booking #${booking.bookingNumber}'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Service Start Failed'),
            content: Text('Failed to start service: $e'),
            actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  Future<void> _downloadInvoice(Booking booking) async {
    try {
      await InvoiceService.downloadInvoice(
        booking: booking,
        customerName: booking.customerName ?? '',
        customerPhone: booking.customerPhone?.isNotEmpty == true
            ? booking.customerPhone
            : null,
        assigneeName: booking.vendorName.isNotEmpty ? booking.vendorName : null,
        generatedBy: 'admin',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate invoice: $e')),
      );
    }
  }

  Future<void> _confirmCancel(Booking booking) async {
    final reasonController = TextEditingController();
    String? capturedReason;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cancel Booking'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cancel booking "${booking.bookingNumber}"?\n\n'
                'The booking will be marked as Cancelled. '
                'This cannot be reversed by the admin.',
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 96,
                child: TextField(
                  controller: reasonController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Cancellation reason (Optional)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () {
              capturedReason = reasonController.text;
              Navigator.of(ctx).pop(true);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (confirmed != true) return;
    final trimmedReason = capturedReason?.trim();
    try {
      await ref.read(bookingsNotifierProvider.notifier).cancelBooking(
            booking.id,
            reason: trimmedReason != null && trimmedReason.isNotEmpty
                ? trimmedReason
                : null,
          );
      await _syncOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking #${booking.bookingNumber} has been cancelled'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Cancel Failed'),
            content: Text('Failed to cancel booking: $e'),
            actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Booking'),
        content: Text(
          'Delete booking "${booking.bookingNumber}"?\n\n'
          'It will be moved to the Restore Bin and can be recovered from there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(bookingsNotifierProvider.notifier).deleteBooking(booking.id);
      await _syncOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('Delete Failed'),
            content: Text('Failed to delete booking: $e'),
            actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(instaHelpOrdersNotifierProvider);
    final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              return Flex(
                direction: narrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'InstaHelp Orders',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage InstaHelp scheduled and instant bookings',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (narrow)
                    const SizedBox(height: 12)
                  else
                    const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(instaHelpOrdersNotifierProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      final created = await showDialog<bool>(
                        context: context,
                        builder: (_) => const AdminCreateInstaHelpBookingDialog(),
                      );
                      if (created == true) {
                        ref.read(instaHelpOrdersNotifierProvider.notifier).refresh();
                      }
                    },
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Create Booking'),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Mode filter chips ─────────────────────────────────────────────
          Row(
            children: [
              _ModeChip(
                label: 'All',
                selected: _modeFilter == null,
                onTap: () => setState(() { _modeFilter = null; _page = 1; }),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                label: 'Scheduled',
                selected: _modeFilter == 'scheduled',
                color: const Color(0xFF3182CE),
                onTap: () => setState(() { _modeFilter = 'scheduled'; _page = 1; }),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                label: 'Instant',
                selected: _modeFilter == 'instant',
                color: const Color(0xFF38A169),
                onTap: () => setState(() { _modeFilter = 'instant'; _page = 1; }),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Filters ──────────────────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminSearchBar(
                hintText: 'Search by booking ID, customer name or phone…',
                width: 300,
                onChanged: (q) => setState(() { _searchQuery = q; _page = 1; }),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    hintText: 'Status',
                    prefixIcon: Icon(Icons.flag_rounded, size: 18),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Status')),
                    ..._allStatuses.map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          _statusConfig[s]?.$1 ??
                              s[0].toUpperCase() + s.substring(1),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() { _statusFilter = v; _page = 1; }),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _assignedToFilter,
                  decoration: const InputDecoration(
                    hintText: 'Assigned To',
                    prefixIcon: Icon(Icons.store_rounded, size: 18),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Assignments')),
                    const DropdownMenuItem(
                        value: _kUnassigned, child: Text('Unassigned')),
                    ...vendors.map(
                      (v) => DropdownMenuItem(
                        value: v.id,
                        child: Text(
                          v.businessName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() { _assignedToFilter = v; _page = 1; }),
                ),
              ),
              InkWell(
                onTap: _pickDateFilter,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        _dateFilter != null
                            ? _dateFmt.format(_dateFilter!)
                            : 'Service Date',
                        style: TextStyle(
                          fontSize: 14,
                          color: _dateFilter != null
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (_dateFilter != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() { _dateFilter = null; _page = 1; }),
                          child: Icon(Icons.close_rounded,
                              size: 14, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: _pickCreatedDateFilter,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _createdDateFilter != null
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_note_rounded,
                          size: 16,
                          color: _createdDateFilter != null
                              ? AppColors.primary
                              : AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        _createdDateFilter != null
                            ? _dateFmt.format(_createdDateFilter!)
                            : 'Created Date',
                        style: TextStyle(
                          fontSize: 14,
                          color: _createdDateFilter != null
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (_createdDateFilter != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() { _createdDateFilter = null; _page = 1; }),
                          child: Icon(Icons.close_rounded,
                              size: 14, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_hasFilters)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _statusFilter = null;
                    _assignedToFilter = null;
                    _dateFilter = null;
                    _createdDateFilter = null;
                    _page = 1;
                  }),
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Table ─────────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load InstaHelp orders',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.toString(),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(instaHelpOrdersNotifierProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final filtered = _applyFilters(all);
                if (all.isEmpty) {
                  return _EmptyState(
                    message: 'No InstaHelp orders yet',
                    sub: 'InstaHelp bookings placed by customers will appear here.',
                  );
                }
                if (filtered.isEmpty) {
                  if (_dateFilter != null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DailySummaryCard(
                          date: _dateFilter!,
                          bookings: const [],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _EmptyState(
                            message: 'No InstaHelp orders for '
                                '${DateFormat('dd MMMM yyyy').format(_dateFilter!)}',
                            sub: 'No InstaHelp bookings are scheduled for this date.',
                          ),
                        ),
                      ],
                    );
                  }
                  return _EmptyState(
                    message: 'No orders match your filters',
                    sub: 'Try adjusting your search or filters.',
                  );
                }
                final paged = filtered
                    .skip((_page - 1) * _pageSize)
                    .take(_pageSize)
                    .toList();
                if (_dateFilter != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DailySummaryCard(
                        date: _dateFilter!,
                        bookings: filtered.map((o) => o.booking).toList(),
                      ),
                      const SizedBox(height: 12),
                      _DateSectionHeader(
                          date: _dateFilter!, count: filtered.length),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _InstaHelpOrdersTable(
                          orders: paged,
                          totalCount: filtered.length,
                          vendors: vendors,
                          onView: (o) => _openDetails(o.booking),
                          onEdit: (o) => _openEditDialog(o.booking),
                          onAssign: (o) => _openAssignDialog(o.booking),
                          onHistory: (o) => _openHistoryDialog(o.booking),
                          onStartDodoService: (o) =>
                              _startDodoService(o.booking),
                          onCancel: (o) => _confirmCancel(o.booking),
                          onDelete: (o) => _confirmDelete(o.booking),
                          onDownloadInvoice: (o) => _downloadInvoice(o.booking),
                          searchQuery: _searchQuery,
                        ),
                      ),
                      PaginationBar(
                        totalItems: filtered.length,
                        currentPage: _page,
                        pageSize: _pageSize,
                        onPageChanged: (p) => setState(() => _page = p),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: _InstaHelpOrdersTable(
                        orders: paged,
                        totalCount: filtered.length,
                        vendors: vendors,
                        onView: (o) => _openDetails(o.booking),
                        onEdit: (o) => _openEditDialog(o.booking),
                        onAssign: (o) => _openAssignDialog(o.booking),
                        onHistory: (o) => _openHistoryDialog(o.booking),
                        onStartDodoService: (o) => _startDodoService(o.booking),
                        onCancel: (o) => _confirmCancel(o.booking),
                        onDelete: (o) => _confirmDelete(o.booking),
                        onDownloadInvoice: (o) => _downloadInvoice(o.booking),
                        searchQuery: _searchQuery,
                      ),
                    ),
                    PaginationBar(
                      totalItems: filtered.length,
                      currentPage: _page,
                      pageSize: _pageSize,
                      onPageChanged: (p) => setState(() => _page = p),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode filter chip ──────────────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? c : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Orders table ──────────────────────────────────────────────────────────────

class _InstaHelpOrdersTable extends StatelessWidget {
  final List<InstaHelpOrder> orders;
  final int totalCount;
  final List<Vendor> vendors;
  final void Function(InstaHelpOrder) onView;
  final void Function(InstaHelpOrder) onEdit;
  final void Function(InstaHelpOrder) onAssign;
  final void Function(InstaHelpOrder) onHistory;
  final void Function(InstaHelpOrder) onStartDodoService;
  final void Function(InstaHelpOrder)? onCancel;
  final void Function(InstaHelpOrder) onDelete;
  final void Function(InstaHelpOrder)? onDownloadInvoice;
  final String searchQuery;

  const _InstaHelpOrdersTable({
    required this.orders,
    required this.totalCount,
    required this.vendors,
    required this.onView,
    required this.onEdit,
    required this.onAssign,
    required this.onHistory,
    required this.onStartDodoService,
    this.onCancel,
    required this.onDelete,
    this.onDownloadInvoice,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < _tableMinWidth
                      ? _tableMinWidth
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TableHeader(),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              key: const PageStorageKey<String>('admin_instahelp_orders'),
                              itemCount: orders.length,
                              separatorBuilder: (context, idx) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final o = orders[i];
                                return _InstaHelpOrderRow(
                                  key: ValueKey(o.booking.id),
                                  order: o,
                                  vendors: vendors,
                                  onView: () => onView(o),
                                  onEdit: () => onEdit(o),
                                  onAssign: () => onAssign(o),
                                  onHistory: () => onHistory(o),
                                  onStartDodoService: () =>
                                      onStartDodoService(o),
                                  onCancel: onCancel != null
                                      ? () => onCancel!(o)
                                      : null,
                                  onDelete: () => onDelete(o),
                                  onDownloadInvoice: onDownloadInvoice != null
                                      ? () => onDownloadInvoice!(o)
                                      : null,
                                  searchQuery: searchQuery,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                orders.length == totalCount
                    ? '${orders.length} order${orders.length == 1 ? '' : 's'}'
                    : '${orders.length} of $totalCount order${totalCount == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _Cell('Booking ID', width: _wId, header: true),
          _Cell('Customer', width: _wCustomer, header: true),
          _Cell('Assigned To', width: _wAssigned, header: true),
          _Cell('Duration', width: _wDuration, header: true),
          _Cell('Service Date', width: _wDate, header: true),
          _Cell('Slot Time', width: _wSlotTime, header: true),
          _Cell('Status', width: _wStatus, header: true),
          _Cell('Total', width: _wTotal, header: true, align: TextAlign.right),
          _Cell('Rating', width: _wRating, header: true,
              padding: const EdgeInsets.only(left: 20)),
          Expanded(
            child: Text(
              'ACTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Order row ─────────────────────────────────────────────────────────────────

class _InstaHelpOrderRow extends StatelessWidget {
  final InstaHelpOrder order;
  final List<Vendor> vendors;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onAssign;
  final VoidCallback onHistory;
  final VoidCallback onStartDodoService;
  final VoidCallback? onCancel;
  final VoidCallback onDelete;
  final VoidCallback? onDownloadInvoice;
  final String searchQuery;

  const _InstaHelpOrderRow({
    super.key,
    required this.order,
    required this.vendors,
    required this.onView,
    required this.onEdit,
    required this.onAssign,
    required this.onHistory,
    required this.onStartDodoService,
    this.onCancel,
    required this.onDelete,
    this.onDownloadInvoice,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final booking = order.booking;
    final serviceDateStr = booking.serviceDate != null
        ? _dateFmt.format(booking.serviceDate!)
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Booking ID
          SizedBox(
            width: _wId,
            child: HighlightedText(
              text: booking.bookingNumber.isNotEmpty
                  ? booking.bookingNumber
                  : booking.id.substring(0, 8),
              query: searchQuery,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Customer
          SizedBox(
            width: _wCustomer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: booking.customerName ?? '',
                  child: HighlightedText(
                    text: booking.customerName ?? '—',
                    query: searchQuery,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: booking.customerName != null
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (booking.customerPhone != null) ...[
                  const SizedBox(height: 2),
                  HighlightedText(
                    text: booking.customerPhone!,
                    query: searchQuery,
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Assigned To
          SizedBox(
            width: _wAssigned,
            child: _AssignedToCell(
              assignmentType: booking.assignmentType,
              vendorId: booking.vendorId,
              dodoTeamId: booking.dodoTeamId,
              vendors: vendors,
              vendorName: booking.vendorName,
            ),
          ),

          // Duration + Mode badge
          SizedBox(
            width: _wDuration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModeBadge(modeType: order.modeType),
                const SizedBox(height: 3),
                Text(
                  order.durationLabel.isNotEmpty ? order.durationLabel : '—',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Service Date
          SizedBox(
            width: _wDate,
            child: booking.serviceDate != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        serviceDateStr,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _weekdayFmt.format(booking.serviceDate!),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF718096),
                        ),
                      ),
                    ],
                  )
                : Text(
                    '—',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
          ),

          // Slot Time
          SizedBox(
            width: _wSlotTime,
            child: Text(
              booking.scheduledTime ?? '—',
              style: TextStyle(
                fontSize: 12,
                color: booking.scheduledTime != null
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),

          // Status
          SizedBox(
            width: _wStatus,
            child: _StatusBadge(booking: booking),
          ),

          // Total
          SizedBox(
            width: _wTotal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _currency.format(booking.totalAmount),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 2),
                Text(
                  booking.paymentMethodLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: booking.isCod
                        ? AppColors.textSecondary
                        : AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),

          // Rating
          SizedBox(
            width: _wRating,
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: booking.review != null
                  ? Tooltip(
                      message: '${booking.review!.rating}/5 stars',
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _StarRating(rating: booking.review!.rating),
                      ),
                    )
                  : Text(
                      '—',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
            ),
          ),

          // Actions
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: onView,
                  icon: Icon(Icons.visibility_rounded,
                      size: 16, color: AppColors.textSecondary),
                  tooltip: 'View details',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_outlined,
                      size: 16, color: AppColors.textSecondary),
                  tooltip: 'Edit booking',
                  visualDensity: VisualDensity.compact,
                ),
                if (_assignableStatuses.contains(booking.status))
                  IconButton(
                    onPressed: onAssign,
                    icon: Icon(
                      booking.isUnassigned
                          ? Icons.assignment_ind_rounded
                          : Icons.swap_horiz_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    tooltip: booking.isUnassigned ? 'Assign' : 'Reassign',
                    visualDensity: VisualDensity.compact,
                  ),
                if (const {'dispatching', 'accepted', 'exhausted'}
                    .contains(booking.dispatchStatus))
                  IconButton(
                    onPressed: onHistory,
                    icon: Icon(Icons.history_rounded,
                        size: 16, color: AppColors.textSecondary),
                    tooltip: 'Assignment history',
                    visualDensity: VisualDensity.compact,
                  ),
                if (booking.status == 'assigned_to_dodo_team')
                  IconButton(
                    onPressed: onStartDodoService,
                    icon: Icon(Icons.play_arrow_rounded,
                        size: 16, color: AppColors.primary),
                    tooltip: 'Start Service (DODO Team)',
                    visualDensity: VisualDensity.compact,
                  ),
                if (onCancel != null &&
                    _cancellableStatuses.contains(booking.status))
                  IconButton(
                    onPressed: onCancel,
                    icon: Icon(Icons.cancel_outlined,
                        size: 16, color: AppColors.error),
                    tooltip: 'Cancel booking',
                    visualDensity: VisualDensity.compact,
                  ),
                if (onDownloadInvoice != null && booking.status == 'completed')
                  IconButton(
                    onPressed: onDownloadInvoice,
                    icon: Icon(Icons.receipt_long_rounded,
                        size: 16, color: AppColors.textSecondary),
                    tooltip: 'Download Invoice',
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: AppColors.error),
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode badge ────────────────────────────────────────────────────────────────

class _ModeBadge extends StatelessWidget {
  final String modeType;
  const _ModeBadge({required this.modeType});

  @override
  Widget build(BuildContext context) {
    final isScheduled = modeType == 'scheduled';
    final color = isScheduled ? const Color(0xFF3182CE) : const Color(0xFF38A169);
    final bg = isScheduled ? const Color(0xFFEBF8FF) : const Color(0xFFEDF7EE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        isScheduled ? 'Scheduled' : 'Instant',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Cell widgets ──────────────────────────────────────────────────────────────

class _AssignedToCell extends StatelessWidget {
  final String assignmentType;
  final String vendorId;
  final String dodoTeamId;
  final List<Vendor> vendors;
  final String vendorName;

  const _AssignedToCell({
    required this.assignmentType,
    required this.vendorId,
    required this.dodoTeamId,
    required this.vendors,
    this.vendorName = '',
  });

  @override
  Widget build(BuildContext context) {
    if (assignmentType == 'DODO Team') {
      return Row(
        children: [
          Icon(Icons.groups_rounded, size: 13, color: AppColors.accent),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'DODO Team',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.accent,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    if (assignmentType == 'Unassigned' ||
        (vendorId.isEmpty && vendorName.isEmpty)) {
      return Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFDD6B20),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Unassigned',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFDD6B20),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    final vendor = vendors.where((v) => v.id == vendorId).firstOrNull;
    final resolvedName = vendor?.businessName ??
        (vendorName.isNotEmpty ? vendorName : 'Unknown Vendor');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFF38A169),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Tooltip(
            message: resolvedName,
            child: Text(
              resolvedName,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Booking booking;
  const _StatusBadge({required this.booking});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = booking.statusConfig;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  final int rating;
  const _StarRating({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 14,
          color: i < rating
              ? const Color(0xFFD69E2E)
              : AppColors.textSecondary.withValues(alpha: 0.4),
        );
      }),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final double width;
  final bool header;
  final TextAlign align;
  final EdgeInsets padding;

  const _Cell(
    this.text, {
    required this.width,
    this.header = false,
    this.align = TextAlign.left,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final style = header
        ? TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          )
        : TextStyle(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w400,
          );
    return SizedBox(
      width: width,
      child: Padding(
        padding: padding,
        child: Text(
          text,
          style: style,
          textAlign: align,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String sub;

  const _EmptyState({required this.message, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.flash_on_rounded,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Daily summary ─────────────────────────────────────────────────────────────

class _DailySummaryCard extends StatelessWidget {
  final DateTime date;
  final List<Booking> bookings;

  const _DailySummaryCard({required this.date, required this.bookings});

  int _count(bool Function(Booking) test) => bookings.where(test).length;

  @override
  Widget build(BuildContext context) {
    final total = bookings.length;
    final pending = _count((b) => b.status == 'pending');
    final accepted = _count((b) =>
        b.status == 'accepted' ||
        (b.status == 'assigned' && b.dispatchStatus == 'accepted'));
    final inProgress = _count((b) =>
        b.status == 'in_progress' ||
        b.status == 'on_the_way' ||
        b.status == 'arrived');
    final completed = _count((b) => b.status == 'completed');
    final cancelled = _count(
        (b) => b.status == 'cancelled' || b.status == 'rejected');

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
              Icon(Icons.bar_chart_rounded, size: 15, color: AppColors.primary),
              const SizedBox(width: 7),
              Text(
                'Daily Summary · ${DateFormat('dd MMMM yyyy').format(date)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SummaryTile(label: 'Total', count: total, color: AppColors.primary),
              const SizedBox(width: 10),
              _SummaryTile(label: 'Pending', count: pending, color: const Color(0xFFDD6B20)),
              const SizedBox(width: 10),
              _SummaryTile(label: 'Accepted', count: accepted, color: const Color(0xFF3182CE)),
              const SizedBox(width: 10),
              _SummaryTile(label: 'In Progress', count: inProgress, color: const Color(0xFF805AD5)),
              const SizedBox(width: 10),
              _SummaryTile(label: 'Completed', count: completed, color: const Color(0xFF38A169)),
              const SizedBox(width: 10),
              _SummaryTile(label: 'Cancelled', count: cancelled, color: const Color(0xFFE53E3E)),
            ].map((w) => Expanded(child: w)).toList(),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DateSectionHeader extends StatelessWidget {
  final DateTime date;
  final int count;

  const _DateSectionHeader({required this.date, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          'InstaHelp orders for ${DateFormat('dd MMMM yyyy').format(date)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count order${count == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}
