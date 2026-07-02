import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/application/providers/auth_provider.dart';
import '../../../notifications/application/providers/notifications_providers.dart';
import '../../../vendor_assignment/application/providers/vendor_assignment_providers.dart';
import '../../../vendor_assignment/domain/models/assignment_entry.dart';
import '../../../vendor_assignment/presentation/widgets/assignment_history_dialog.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../../vendors/domain/models/vendor.dart';
import '../../application/providers/bookings_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/booking_item.dart';
import '../widgets/booking_details_dialog.dart';
import '../widgets/booking_assignment_dialog.dart';
import '../widgets/create_booking_dialog.dart';

// ── Column widths ─────────────────────────────────────────────────────────────

const double _wId = 130;
const double _wAssigned = 160;
const double _wService = 190;
const double _wDate = 110;
const double _wStatus = 130;
const double _wTotal = 140;
const double _wRating = 120;
const double _wActions = 200;
const double _tableMinWidth =
    _wId + _wAssigned + _wService + _wDate + _wStatus + _wTotal + _wRating + _wActions;

// ── Status display config ─────────────────────────────────────────────────────

const _statusConfig = <String, (String, Color, Color)>{
  'pending':               ('Pending',            Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'assigned':              ('Assigned',            Color(0xFF3182CE), Color(0xFFEBF8FF)),
  'assigned_to_dodo_team': ('DODO Assigned',       Color(0xFF6B46C1), Color(0xFFF3E8FF)),
  'accepted':              ('Accepted',            Color(0xFF2C7A7B), Color(0xFFE6FFFA)),
  'on_the_way':            ('On The Way',          Color(0xFF4A6FA5), Color(0xFFEBF4FF)),
  'arrived':               ('Arrived',             Color(0xFF6B46C1), Color(0xFFF3E8FF)),
  'in_progress':           ('In Progress',         Color(0xFF805AD5), Color(0xFFFAF5FF)),
  'completed':             ('Completed',           Color(0xFF38A169), Color(0xFFF0FFF4)),
  'rejected':              ('Rejected',            Color(0xFFC05621), Color(0xFFFEEBC8)),
  'cancelled':             ('Cancelled',           Color(0xFFE53E3E), Color(0xFFFFF5F5)),
};

const _allStatuses = [
  'pending',
  'assigned',
  'assigned_to_dodo_team',
  'accepted',
  'on_the_way',
  'arrived',
  'in_progress',
  'completed',
  'rejected',
  'cancelled',
];

// Statuses that admin can still cancel from (active lifecycle)
const _cancellableStatuses = {
  'pending', 'assigned', 'assigned_to_dodo_team', 'accepted', 'on_the_way', 'arrived', 'in_progress',
};

// Sentinel for the "Unassigned" option in the Assigned To filter.
const String _kUnassigned = '__unassigned__';

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('dd MMM yyyy');

// ── Page ──────────────────────────────────────────────────────────────────────

class BookingsPage extends ConsumerStatefulWidget {
  const BookingsPage({super.key});

  @override
  ConsumerState<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends ConsumerState<BookingsPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _statusFilter;
  String? _assignedToFilter; // null = All, _kUnassigned = Unassigned, vendorId = specific vendor
  DateTime? _dateFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _vendorName(String vendorId) {
    if (vendorId.isEmpty) return '';
    final vendors = ref.read(vendorsNotifierProvider).valueOrNull ?? [];
    final match = vendors.where((v) => v.id == vendorId);
    if (match.isEmpty) {
      return vendorId.length > 8
          ? '${vendorId.substring(0, 8)}…'
          : vendorId;
    }
    return match.first.businessName;
  }

  // ── Filters ──────────────────────────────────────────────────────────────────

  List<Booking> _applyFilters(List<Booking> all) {
    var result = all;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((b) => b.bookingNumber.toLowerCase().contains(q))
          .toList();
    }
    if (_statusFilter != null) {
      result = result.where((b) => b.status == _statusFilter).toList();
    }
    if (_assignedToFilter == _kUnassigned) {
      result = result.where((b) => b.isUnassigned).toList();
    } else if (_assignedToFilter != null) {
      result =
          result.where((b) => b.vendorId == _assignedToFilter).toList();
    }
    if (_dateFilter != null) {
      result = result.where((b) {
        if (b.serviceDate == null) return false;
        final d = b.serviceDate!;
        return d.year == _dateFilter!.year &&
            d.month == _dateFilter!.month &&
            d.day == _dateFilter!.day;
      }).toList();
    }
    return result;
  }

  bool get _hasFilters =>
      _statusFilter != null ||
      _assignedToFilter != null ||
      _dateFilter != null;

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _dateFilter = picked);
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  void _openCreate() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateBookingDialog(
        onCreate: ({
          required customerId,
          required serviceDate,
          required address,
          notes,
          required items,
        }) async {
          await ref.read(bookingsNotifierProvider.notifier).createBooking(
                customerId: customerId,
                serviceDate: serviceDate,
                address: address,
                notes: notes,
                items: items,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Booking created successfully')),
            );
          }
        },
      ),
    );
  }

  void _openDetails(Booking booking) {
    showDialog(
      context: context,
      builder: (_) => BookingDetailsDialog(
        booking: booking,
        onAssign: () {
          Navigator.of(context).pop();
          _openAssignDialog(booking);
        },
        onCancel: _cancellableStatuses.contains(booking.status)
            ? () {
                Navigator.of(context).pop();
                _confirmCancel(booking);
              }
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
                    title: 'New Booking Assigned',
                    message:
                        'You have been assigned booking #${booking.bookingNumber}.',
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
                        ? 'A service provider has been assigned to your booking.'
                        : 'A new service provider has been assigned to your booking.',
                    notificationType: isFirstAssignment
                        ? 'vendor_assigned'
                        : 'vendor_reassigned',
                    entityType: 'booking',
                    entityId: booking.id,
                  );
            } catch (_) {}
          }

          ref
              .read(vendorAssignmentHistoryProvider.notifier)
              .addEntry(AssignmentEntry(
                bookingId: booking.id,
                bookingNumber: booking.bookingNumber,
                previousVendorId: previousVendorId,
                previousVendorName: previousVendorName,
                newVendorId: vendorId ?? '',
                newVendorName: assigneeName,
                assignedAt: DateTime.now(),
                adminName: adminUser?.displayName ?? 'Admin',
              ));

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
    final history = ref
        .read(vendorAssignmentHistoryProvider.notifier)
        .forBooking(booking.id);
    showDialog(
      context: context,
      builder: (_) => AssignmentHistoryDialog(
        bookingNumber: booking.bookingNumber,
        entries: history,
      ),
    );
  }

  Future<void> _confirmCancel(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cancel Booking'),
        content: Text(
          'Cancel booking "${booking.bookingNumber}"?\n\n'
          'The booking will be marked as Cancelled. '
          'This cannot be reversed by the admin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(bookingsNotifierProvider.notifier)
          .cancelBooking(booking.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Booking #${booking.bookingNumber} has been cancelled'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cancel failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _startDodoService(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

      // Notify customer that service has started.
      try {
        await ref
            .read(notificationsNotifierProvider.notifier)
            .createNotification(
              userType: 'customer',
              userId: booking.customerId,
              title: 'Service Started',
              message: 'Your service is now in progress by the DODO Team.',
              notificationType: 'vendor_started',
              entityType: 'booking',
              entityId: booking.id,
            );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Service started for booking #${booking.bookingNumber}'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start service: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Booking'),
        content: Text(
          'Are you sure you want to delete booking '
          '"${booking.bookingNumber}"?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(bookingsNotifierProvider.notifier)
          .deleteBooking(booking.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingsNotifierProvider);
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
                        'Bookings',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manage the full booking lifecycle',
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(bookingsNotifierProvider.notifier)
                            .refresh(),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Refresh'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _openCreate,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('New Booking'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Filters ──────────────────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Search
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search booking ID…',
                    prefixIcon:
                        const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.trim()),
                ),
              ),

              // Status
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    hintText: 'Status',
                    prefixIcon: Icon(Icons.flag_rounded, size: 18),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Status')),
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
                      setState(() => _statusFilter = v),
                ),
              ),

              // Assigned To
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _assignedToFilter,
                  decoration: const InputDecoration(
                    hintText: 'Assigned To',
                    prefixIcon:
                        Icon(Icons.store_rounded, size: 18),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Assignments')),
                    const DropdownMenuItem(
                        value: _kUnassigned,
                        child: Text('Unassigned')),
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
                      setState(() => _assignedToFilter = v),
                ),
              ),

              // Service Date
              InkWell(
                onTap: _pickDateFilter,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 46,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 16,
                          color: AppColors.textSecondary),
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
                          onTap: () =>
                              setState(() => _dateFilter = null),
                          child: Icon(Icons.close_rounded,
                              size: 14,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Clear
              if (_hasFilters)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _statusFilter = null;
                    _assignedToFilter = null;
                    _dateFilter = null;
                  }),
                  icon: const Icon(Icons.filter_alt_off_rounded,
                      size: 16),
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
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load bookings',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.toString(),
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(bookingsNotifierProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded,
                          size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final filtered = _applyFilters(all);
                if (all.isEmpty) {
                  return _EmptyState(
                    message: 'No bookings yet',
                    sub: 'Create a booking or wait for customers to place orders.',
                    onAction: _openCreate,
                    actionLabel: 'New Booking',
                  );
                }
                if (filtered.isEmpty) {
                  return _EmptyState(
                    message: 'No bookings match your filters',
                    sub: 'Try adjusting your search or filters.',
                  );
                }
                return _BookingsTable(
                  bookings: filtered,
                  totalCount: all.length,
                  vendors: vendors,
                  onView: _openDetails,
                  onAssign: _openAssignDialog,
                  onHistory: _openHistoryDialog,
                  onStartDodoService: _startDodoService,
                  onCancel: _confirmCancel,
                  onDelete: _confirmDelete,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Table ──────────────────────────────────────────────────────────────────────

class _BookingsTable extends StatelessWidget {
  final List<Booking> bookings;
  final int totalCount;
  final List<Vendor> vendors;
  final void Function(Booking) onView;
  final void Function(Booking) onAssign;
  final void Function(Booking) onHistory;
  final void Function(Booking) onStartDodoService;
  final void Function(Booking) onCancel;
  final void Function(Booking) onDelete;

  const _BookingsTable({
    required this.bookings,
    required this.totalCount,
    required this.vendors,
    required this.onView,
    required this.onAssign,
    required this.onHistory,
    required this.onStartDodoService,
    required this.onCancel,
    required this.onDelete,
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
                  final tableWidth =
                      constraints.maxWidth < _tableMinWidth
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
                              itemCount: bookings.length,
                              separatorBuilder: (_, idx) =>
                                  const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final b = bookings[i];
                                return _BookingRow(
                                  booking: b,
                                  vendors: vendors,
                                  onView: () => onView(b),
                                  onAssign: () => onAssign(b),
                                  onHistory: () => onHistory(b),
                                  onStartDodoService: () => onStartDodoService(b),
                                  onCancel: () => onCancel(b),
                                  onDelete: () => onDelete(b),
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
            // Footer count
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Text(
                bookings.length == totalCount
                    ? '${bookings.length} booking${bookings.length == 1 ? '' : 's'}'
                    : '${bookings.length} of $totalCount booking${totalCount == 1 ? '' : 's'}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
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
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _Cell('Booking ID', width: _wId, header: true),
          _Cell('Assigned To', width: _wAssigned, header: true),
          _Cell('Service', width: _wService, header: true),
          _Cell('Service Date', width: _wDate, header: true),
          _Cell('Status', width: _wStatus, header: true),
          _Cell('Total', width: _wTotal, header: true, align: TextAlign.right),
          _Cell('Rating', width: _wRating, header: true,
              padding: const EdgeInsets.only(left: 20)),
          _Cell('Actions', width: _wActions, header: true, align: TextAlign.center),
        ],
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  final Booking booking;
  final List<Vendor> vendors;
  final VoidCallback onView;
  final VoidCallback onAssign;
  final VoidCallback onHistory;
  final VoidCallback onStartDodoService;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _BookingRow({
    required this.booking,
    required this.vendors,
    required this.onView,
    required this.onAssign,
    required this.onHistory,
    required this.onStartDodoService,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final serviceDateStr = booking.serviceDate != null
        ? _dateFmt.format(booking.serviceDate!)
        : '—';

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Booking ID
          SizedBox(
            width: _wId,
            child: Text(
              booking.bookingNumber.isNotEmpty
                  ? booking.bookingNumber
                  : booking.id.substring(0, 8),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
              overflow: TextOverflow.ellipsis,
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
            ),
          ),

          // Service
          SizedBox(
            width: _wService,
            child: _ServiceCell(items: booking.items),
          ),

          // Service Date
          _Cell(serviceDateStr, width: _wDate),

          // Status
          SizedBox(
            width: _wStatus,
            child: _StatusBadge(status: booking.status),
          ),

          // Total Amount
          _Cell(
            _currency.format(booking.totalAmount),
            width: _wTotal,
            align: TextAlign.right,
            bold: true,
          ),

          // Rating
          SizedBox(
            width: _wRating,
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: booking.review != null
                  ? _StarRating(rating: booking.review!.rating)
                  : Text(
                      '—',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary),
                    ),
            ),
          ),

          // Actions
          SizedBox(
            width: _wActions,
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
                if (_cancellableStatuses.contains(booking.status))
                  IconButton(
                    onPressed: onCancel,
                    icon: Icon(Icons.cancel_outlined,
                        size: 16, color: AppColors.error),
                    tooltip: 'Cancel booking',
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

// ── Cell widgets ──────────────────────────────────────────────────────────────

class _AssignedToCell extends StatelessWidget {
  final String assignmentType;
  final String vendorId;
  final String dodoTeamId;
  final List<Vendor> vendors;

  const _AssignedToCell({
    required this.assignmentType,
    required this.vendorId,
    required this.dodoTeamId,
    required this.vendors,
  });

  @override
  Widget build(BuildContext context) {
    if (assignmentType == 'DODO Team') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_rounded, size: 13, color: AppColors.accent),
          const SizedBox(width: 5),
          const Text(
            'DODO Team',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    if (assignmentType == 'Unassigned') {
      return Row(
        mainAxisSize: MainAxisSize.min,
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
          const Text(
            'Unassigned',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFFDD6B20),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    // External Vendor
    final vendor = vendors.where((v) => v.id == vendorId).firstOrNull;
    if (vendor != null) {
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
            child: Text(
              vendor.businessName,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Text(
      vendorId.length > 8 ? '${vendorId.substring(0, 8)}…' : vendorId,
      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
}

class _ServiceCell extends StatelessWidget {
  final List<BookingItem> items;

  const _ServiceCell({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        '—',
        style:
            TextStyle(fontSize: 13, color: AppColors.textSecondary),
      );
    }
    final first = items.first;
    final extra = items.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          first.serviceName.isNotEmpty ? first.serviceName : '—',
          style: const TextStyle(
              fontSize: 13, color: AppColors.textPrimary),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF8FF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+$extra more',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3182CE),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final cfg = _statusConfig[status];
    final label = cfg?.$1 ?? status;
    final color = cfg?.$2 ?? AppColors.textSecondary;
    final bg = cfg?.$3 ?? AppColors.background;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle),
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

// ── Shared cell ───────────────────────────────────────────────────────────────

class _Cell extends StatelessWidget {
  final String text;
  final double width;
  final bool header;
  final bool bold;
  final TextAlign align;
  final EdgeInsets padding;

  const _Cell(
    this.text, {
    required this.width,
    this.header = false,
    this.bold = false,
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
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
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
  final VoidCallback? onAction;
  final String? actionLabel;

  const _EmptyState({
    required this.message,
    required this.sub,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.book_online_outlined,
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
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(actionLabel!),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
