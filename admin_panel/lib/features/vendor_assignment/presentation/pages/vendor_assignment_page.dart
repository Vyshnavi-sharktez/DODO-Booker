import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../../bookings/application/providers/bookings_providers.dart';
import '../../../bookings/domain/models/booking.dart';
import '../../../customers/application/providers/customers_providers.dart';
import '../../../notifications/application/providers/notifications_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../application/providers/vendor_assignment_providers.dart';
import '../../domain/models/assignment_entry.dart';
import '../widgets/assign_vendor_dialog.dart';
import '../widgets/assignment_history_dialog.dart';

final _dateFmt = DateFormat('dd MMM yyyy');
final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

// ── Status filter ─────────────────────────────────────────────────────────────

enum _AssignFilter { all, pending, assigned, inProgress, rejected }

const _statusBadgeData = <String, (String, Color, Color)>{
  'pending': ('Pending', Color(0xFFF6E05E), Color(0xFF744210)),
  'assigned': ('Assigned', Color(0xFF90CDF4), Color(0xFF1A365D)),
  'in_progress': ('In Progress', Color(0xFF9AE6B4), Color(0xFF1C4532)),
  'completed': ('Completed', Color(0xFFC6F6D5), Color(0xFF276749)),
  'cancelled': ('Cancelled', Color(0xFFFED7D7), Color(0xFF742A2A)),
  'rejected': ('Rejected', Color(0xFFFEB2B2), Color(0xFF742A2A)),
};

// ── Page ──────────────────────────────────────────────────────────────────────

class VendorAssignmentPage extends ConsumerStatefulWidget {
  const VendorAssignmentPage({super.key});

  @override
  ConsumerState<VendorAssignmentPage> createState() =>
      _VendorAssignmentPageState();
}

class _VendorAssignmentPageState
    extends ConsumerState<VendorAssignmentPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _AssignFilter _filter = _AssignFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _customerName(String customerId) {
    final customers =
        ref.read(customersNotifierProvider).valueOrNull ?? [];
    final match = customers.where((c) => c.id == customerId);
    if (match.isEmpty) {
      return customerId.length > 8
          ? '${customerId.substring(0, 8)}…'
          : customerId;
    }
    return match.first.fullName.isEmpty
        ? match.first.email
        : match.first.fullName;
  }

  String _vendorName(String vendorId) {
    if (vendorId.isEmpty) return '';
    final vendors = ref.read(vendorsNotifierProvider).valueOrNull ?? [];
    final match = vendors.where((v) => v.id == vendorId);
    if (match.isEmpty) {
      return vendorId.length > 8 ? '${vendorId.substring(0, 8)}…' : vendorId;
    }
    return match.first.businessName;
  }

  List<Booking> _applyFilters(List<Booking> all) {
    // Show actionable bookings: pending, assigned, in_progress, and rejected
    // (admin can reassign rejected bookings).
    var result = all
        .where((b) =>
            b.status == 'pending' ||
            b.status == 'assigned' ||
            b.status == 'in_progress' ||
            b.status == 'rejected')
        .toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((b) => b.bookingNumber.toLowerCase().contains(q))
          .toList();
    }

    switch (_filter) {
      case _AssignFilter.pending:
        result = result.where((b) => b.status == 'pending').toList();
      case _AssignFilter.assigned:
        result = result.where((b) => b.status == 'assigned').toList();
      case _AssignFilter.inProgress:
        result = result.where((b) => b.status == 'in_progress').toList();
      case _AssignFilter.rejected:
        result = result.where((b) => b.status == 'rejected').toList();
      case _AssignFilter.all:
        break;
    }
    return result;
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openAssignDialog(Booking booking) {
    final customerName = _customerName(booking.customerId);
    final currentVendorName =
        booking.vendorId.isNotEmpty ? _vendorName(booking.vendorId) : '';
    final adminUser = ref.read(currentAdminUserProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AssignVendorDialog(
        booking: booking,
        customerName: customerName,
        currentVendorName: currentVendorName,
        onAssign: ({
          required vendorId,
          required vendorName,
          required serviceDate,
          required status,
          notes,
        }) async {
          final previousVendorId =
              booking.vendorId.isNotEmpty ? booking.vendorId : null;
          final previousVendorName =
              previousVendorId != null ? _vendorName(previousVendorId) : '';
          final isFirstAssignment = previousVendorId == null;

          debugPrint(
            '[DODO][VendorAssignment] Assignment detected: '
            'booking #${booking.bookingNumber} → vendor $vendorName'
            '${isFirstAssignment ? '' : ' (reassignment from $previousVendorName)'}',
          );

          // Update booking — the DB trigger fires here and creates the
          // customer notification automatically.
          await ref
              .read(bookingsNotifierProvider.notifier)
              .updateBooking(
                booking.id,
                vendorId: vendorId,
                serviceDate: serviceDate,
                status: status,
                notes: notes,
              );

          // Create notification for vendor.
          try {
            await ref
                .read(notificationsNotifierProvider.notifier)
                .createNotification(
                  userType: 'vendor',
                  userId: vendorId,
                  title: booking.status == 'rejected'
                      ? 'Booking Reassigned to You'
                      : 'New Booking Assigned',
                  message: booking.status == 'rejected'
                      ? 'Booking #${booking.bookingNumber} has been reassigned to you.'
                      : 'Booking #${booking.bookingNumber} has been assigned to you.',
                  notificationType: 'booking',
                );
            debugPrint(
              '[DODO][VendorAssignment] Notification created: '
              'vendor $vendorId notified for booking #${booking.bookingNumber}',
            );
          } catch (_) {
            // Notification failure must not block assignment.
          }

          // Record in-memory history entry.
          ref
              .read(vendorAssignmentHistoryProvider.notifier)
              .addEntry(AssignmentEntry(
                bookingId: booking.id,
                bookingNumber: booking.bookingNumber,
                previousVendorId: previousVendorId,
                previousVendorName: previousVendorName,
                newVendorId: vendorId,
                newVendorName: vendorName,
                assignedAt: DateTime.now(),
                adminName: adminUser?.displayName ?? 'Admin',
              ));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  previousVendorId != null
                      ? 'Booking #${booking.bookingNumber} reassigned to $vendorName'
                      : 'Booking #${booking.bookingNumber} assigned to $vendorName',
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
    final history = ref.read(vendorAssignmentHistoryProvider
        .notifier)
        .forBooking(booking.id);
    showDialog(
      context: context,
      builder: (_) => AssignmentHistoryDialog(
        bookingNumber: booking.bookingNumber,
        entries: history,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bookingsState = ref.watch(bookingsNotifierProvider);
    final unassigned = ref.watch(unassignedBookingsCountProvider);
    final assigned = ref.watch(assignedBookingsCountProvider);
    final inProgress = ref.watch(inProgressBookingsCountProvider);
    final rejected = ref.watch(rejectedBookingsCountProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ───────────────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vendor Assignment',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Assign and manage vendors for active bookings',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Stats row ─────────────────────────────────────────────────────
          Row(
            children: [
              _StatCard(
                label: 'Unassigned',
                value: '$unassigned',
                icon: Icons.assignment_late_rounded,
                color: const Color(0xFFDD6B20),
              ),
              const SizedBox(width: 12),
              _StatCard(
                label: 'Assigned',
                value: '$assigned',
                icon: Icons.assignment_ind_rounded,
                color: const Color(0xFF3182CE),
              ),
              const SizedBox(width: 12),
              _StatCard(
                label: 'In Progress',
                value: '$inProgress',
                icon: Icons.pending_actions_rounded,
                color: AppColors.success,
              ),
              const SizedBox(width: 12),
              _StatCard(
                label: 'Rejected',
                value: '$rejected',
                icon: Icons.cancel_outlined,
                color: AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Search + Filter chips ─────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search booking number…',
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
              _Chip(
                label: 'All',
                selected: _filter == _AssignFilter.all,
                onTap: () =>
                    setState(() => _filter = _AssignFilter.all),
              ),
              _Chip(
                label: 'Unassigned',
                selected: _filter == _AssignFilter.pending,
                color: const Color(0xFFDD6B20),
                onTap: () =>
                    setState(() => _filter = _AssignFilter.pending),
              ),
              _Chip(
                label: 'Assigned',
                selected: _filter == _AssignFilter.assigned,
                color: const Color(0xFF3182CE),
                onTap: () =>
                    setState(() => _filter = _AssignFilter.assigned),
              ),
              _Chip(
                label: 'In Progress',
                selected: _filter == _AssignFilter.inProgress,
                color: AppColors.success,
                onTap: () => setState(
                    () => _filter = _AssignFilter.inProgress),
              ),
              _Chip(
                label: 'Rejected',
                selected: _filter == _AssignFilter.rejected,
                color: AppColors.error,
                onTap: () =>
                    setState(() => _filter = _AssignFilter.rejected),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Table ─────────────────────────────────────────────────────────
          Expanded(
            child: bookingsState.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text('Failed to load bookings',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Text(e.toString(),
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref
                          .read(bookingsNotifierProvider.notifier)
                          .refresh(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final actionable = all
                    .where((b) =>
                        b.status == 'pending' ||
                        b.status == 'assigned' ||
                        b.status == 'in_progress' ||
                        b.status == 'rejected')
                    .toList();
                final filtered = _applyFilters(all);

                if (actionable.isEmpty) {
                  return const _EmptyState(
                    message: 'No bookings require attention',
                    sub: 'All bookings are completed or cancelled.',
                  );
                }
                if (filtered.isEmpty) {
                  return const _EmptyState(
                    message: 'No bookings match your filters',
                    sub: 'Try adjusting your search or filter.',
                  );
                }
                return _AssignmentTable(
                  bookings: filtered,
                  totalCount: all.length,
                  customerNameResolver: _customerName,
                  vendorNameResolver: _vendorName,
                  onAssign: _openAssignDialog,
                  onHistory: _openHistoryDialog,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    this.color = AppColors.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.1)
              : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? color : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Assignment table ──────────────────────────────────────────────────────────

class _AssignmentTable extends StatelessWidget {
  final List<Booking> bookings;
  final int totalCount;
  final String Function(String) customerNameResolver;
  final String Function(String) vendorNameResolver;
  final void Function(Booking) onAssign;
  final void Function(Booking) onHistory;

  const _AssignmentTable({
    required this.bookings,
    required this.totalCount,
    required this.customerNameResolver,
    required this.vendorNameResolver,
    required this.onAssign,
    required this.onHistory,
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
            // Header
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: const Row(
                children: [
                  _HCell('Booking #', flex: 2),
                  _HCell('Customer', flex: 3),
                  _HCell('Amount', flex: 2),
                  _HCell('Service Date', flex: 2),
                  _HCell('Status', flex: 2),
                  _HCell('Vendor / Reason', flex: 3),
                  _HCell('Actions', flex: 2, align: TextAlign.center),
                ],
              ),
            ),
            const Divider(height: 1),
            // Rows
            Expanded(
              child: ListView.separated(
                itemCount: bookings.length,
                separatorBuilder: (ctx, i) =>
                    const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  return _BookingAssignRow(
                    booking: bookings[i],
                    customerName:
                        customerNameResolver(bookings[i].customerId),
                    vendorName:
                        vendorNameResolver(bookings[i].vendorId),
                    onAssign: () => onAssign(bookings[i]),
                    onHistory: () => onHistory(bookings[i]),
                  );
                },
              ),
            ),
            // Footer
            Container(
              color: AppColors.background,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              child: Text(
                '${bookings.length} booking${bookings.length == 1 ? '' : 's'}',
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

class _HCell extends StatelessWidget {
  final String label;
  final int flex;
  final TextAlign align;

  const _HCell(this.label,
      {required this.flex, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
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

class _BookingAssignRow extends StatelessWidget {
  final Booking booking;
  final String customerName;
  final String vendorName;
  final VoidCallback onAssign;
  final VoidCallback onHistory;

  const _BookingAssignRow({
    required this.booking,
    required this.customerName,
    required this.vendorName,
    required this.onAssign,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final badge = _statusBadgeData[b.status] ??
        ('Unknown', AppColors.border, AppColors.textSecondary);
    final serviceDateStr =
        b.serviceDate != null ? _dateFmt.format(b.serviceDate!) : '—';
    final isUnassigned = b.vendorId.isEmpty || b.status == 'pending';
    final isRejected = b.status == 'rejected';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Booking number
          Expanded(
            flex: 2,
            child: Text(
              b.bookingNumber,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Customer
          Expanded(
            flex: 3,
            child: Text(
              customerName,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Amount
          Expanded(
            flex: 2,
            child: Text(
              _currency.format(b.totalAmount),
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),

          // Service Date
          Expanded(
            flex: 2,
            child: Text(
              serviceDateStr,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
          ),

          // Status badge
          Expanded(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badge.$2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge.$1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: badge.$3,
                  ),
                ),
              ),
            ),
          ),

          // Vendor name + rejection reason (if rejected)
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isUnassigned)
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDD6B20)
                              .withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        'Unassigned',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary
                              .withValues(alpha: 0.7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    vendorName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (isRejected &&
                    b.rejectionReason != null &&
                    b.rejectionReason!.isNotEmpty)
                  Text(
                    'Reason: ${b.rejectionReason}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontStyle: FontStyle.italic,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                if (isRejected && b.rejectedAt != null)
                  Text(
                    'At: ${_dateFmt.format(b.rejectedAt!)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Actions
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Tooltip(
                  message: isUnassigned
                      ? 'Assign Vendor'
                      : isRejected
                          ? 'Reassign Vendor'
                          : 'Reassign Vendor',
                  child: TextButton.icon(
                    onPressed: onAssign,
                    icon: Icon(
                      isUnassigned
                          ? Icons.assignment_ind_rounded
                          : Icons.swap_horiz_rounded,
                      size: 14,
                    ),
                    label: Text(
                      isUnassigned ? 'Assign' : 'Reassign',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: isRejected
                          ? AppColors.error
                          : isUnassigned
                              ? AppColors.primary
                              : AppColors.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onHistory,
                  icon: const Icon(Icons.history_rounded, size: 15),
                  tooltip: 'History',
                  color: AppColors.textSecondary,
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
            Icons.assignment_outlined,
            size: 56,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
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
          Text(sub,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
