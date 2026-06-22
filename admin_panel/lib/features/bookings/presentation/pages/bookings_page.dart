import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../application/providers/bookings_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/booking_item.dart';
import '../widgets/booking_details_dialog.dart';
import '../widgets/booking_assignment_dialog.dart';

// ── Status display config ─────────────────────────────────────────────────────

const _statusConfig = <String, (String, Color, Color)>{
  'pending': ('Pending', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'assigned': ('Assigned', Color(0xFF3182CE), Color(0xFFEBF8FF)),
  'in_progress': ('In Progress', Color(0xFF805AD5), Color(0xFFFAF5FF)),
  'completed': ('Completed', Color(0xFF38A169), Color(0xFFF0FFF4)),
  'cancelled': ('Cancelled', Color(0xFFE53E3E), Color(0xFFFFF5F5)),
};

const _allStatuses = [
  'pending',
  'assigned',
  'in_progress',
  'completed',
  'cancelled',
];

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
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
  DateTime? _dateFilter;
  String? _reviewStatusFilter; // 'reviewed' | 'not_reviewed' | null
  int? _ratingFilter;           // 1–5 | null

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
    if (_dateFilter != null) {
      result = result.where((b) {
        if (b.serviceDate == null) return false;
        final d = b.serviceDate!;
        return d.year == _dateFilter!.year &&
            d.month == _dateFilter!.month &&
            d.day == _dateFilter!.day;
      }).toList();
    }
    if (_reviewStatusFilter == 'reviewed') {
      result = result.where((b) => b.review != null).toList();
    } else if (_reviewStatusFilter == 'not_reviewed') {
      result = result.where((b) => b.review == null).toList();
    }
    if (_ratingFilter != null) {
      result = result
          .where((b) => b.review?.rating == _ratingFilter)
          .toList();
    }
    return result;
  }

  bool get _hasFilters =>
      _statusFilter != null ||
      _dateFilter != null ||
      _reviewStatusFilter != null ||
      _ratingFilter != null;

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFilter ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _dateFilter = picked);
  }

  void _openDetails(Booking booking) {
    showDialog(
      context: context,
      builder: (_) => BookingDetailsDialog(booking: booking),
    );
  }

  void _openEdit(Booking booking) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingAssignmentDialog(
        booking: booking,
        onSave: ({
          required vendorId,
          required serviceDate,
          required status,
          notes,
        }) async {
          await ref.read(bookingsNotifierProvider.notifier).updateBooking(
                booking.id,
                vendorId: vendorId,
                serviceDate: serviceDate,
                status: status,
                notes: notes,
              );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Booking updated successfully')),
            );
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingsNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Responsive Header ─────────────────────────────────────────────
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
                  if (narrow) const SizedBox(height: 12) else const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => ref
                        .read(bookingsNotifierProvider.notifier)
                        .refresh(),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Search + Filters ──────────────────────────────────────────────
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Search
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search booking number…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
              ),

              // Status filter
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _statusFilter,
                  decoration: const InputDecoration(
                    hintText: 'All Statuses',
                    prefixIcon: Icon(Icons.flag_rounded, size: 18),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Statuses')),
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
                  onChanged: (v) => setState(() => _statusFilter = v),
                ),
              ),

              // Date filter
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
                    ],
                  ),
                ),
              ),

              // Review status filter
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _reviewStatusFilter,
                  decoration: const InputDecoration(
                    hintText: 'All Reviews',
                    prefixIcon: Icon(Icons.rate_review_rounded, size: 18),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All Reviews')),
                    DropdownMenuItem(
                        value: 'reviewed', child: Text('Reviewed')),
                    DropdownMenuItem(
                        value: 'not_reviewed', child: Text('Not Reviewed')),
                  ],
                  onChanged: (v) =>
                      setState(() => _reviewStatusFilter = v),
                ),
              ),

              // Rating filter
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  // ignore: deprecated_member_use
                  value: _ratingFilter,
                  decoration: const InputDecoration(
                    hintText: 'All Ratings',
                    prefixIcon: Icon(Icons.star_rounded, size: 18),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Ratings')),
                    ...List.generate(
                      5,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1} Star${i > 0 ? 's' : ''}'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _ratingFilter = v),
                ),
              ),

              // Clear filters
              if (_hasFilters)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _statusFilter = null;
                    _dateFilter = null;
                    _reviewStatusFilter = null;
                    _ratingFilter = null;
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

          // ── Body ──────────────────────────────────────────────────────────
          Expanded(
            child: state.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
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
                          color: AppColors.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
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
                final filtered = _applyFilters(all);
                if (all.isEmpty) {
                  return _EmptyState(
                    message: 'No bookings yet',
                    sub: 'Bookings will appear here once customers place orders.',
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
                  onView: _openDetails,
                  onEdit: _openEdit,
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

class _BookingsTable extends ConsumerWidget {
  final List<Booking> bookings;
  final int totalCount;
  final void Function(Booking) onView;
  final void Function(Booking) onEdit;
  final void Function(Booking) onDelete;

  const _BookingsTable({
    required this.bookings,
    required this.totalCount,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];

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
            // Scrollable table
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < 1590
                      ? 1590.0
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
                                final vendor = vendors
                                    .where((v) => v.id == b.vendorId)
                                    .firstOrNull;
                                return _BookingRow(
                                  booking: b,
                                  vendorName: vendor?.businessName,
                                  onView: () => onView(b),
                                  onEdit: () => onEdit(b),
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
            // Footer
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _Cell('Booking #', width: 130, header: true),
          _Cell('Customer ID', width: 110, header: true),
          _Cell('Vendor', width: 140, header: true),
          _Cell('Service Date', width: 110, header: true),
          _Cell('Status', width: 120, header: true),
          _Cell('Services', width: 160, header: true),
          _Cell('Subtotal', width: 90, header: true, align: TextAlign.right),
          _Cell('Discount', width: 90, header: true, align: TextAlign.right),
          _Cell('Total', width: 100, header: true, align: TextAlign.right),
          _Cell('Created', width: 110, header: true),
          _Cell('Review', width: 110, header: true),
          _Cell('Rating', width: 110, header: true),
          _Cell('Actions', width: 110, header: true, align: TextAlign.center),
        ],
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  final Booking booking;
  final String? vendorName;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BookingRow({
    required this.booking,
    required this.vendorName,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final createdStr = booking.createdAt != null
        ? _dateFmt.format(booking.createdAt!)
        : '—';
    final serviceDateStr = booking.serviceDate != null
        ? _dateFmt.format(booking.serviceDate!)
        : '—';
    final vendorDisplay = vendorName ??
        (booking.vendorId.length > 8
            ? '${booking.vendorId.substring(0, 8)}…'
            : booking.vendorId);
    final customerDisplay = booking.customerId.length > 8
        ? '${booking.customerId.substring(0, 8)}…'
        : booking.customerId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          _Cell(
            booking.bookingNumber,
            width: 130,
            bold: true,
            color: AppColors.accent,
          ),
          _Cell(customerDisplay, width: 110,
              tooltip: booking.customerId),
          _Cell(vendorDisplay, width: 140,
              tooltip: booking.vendorId),
          _Cell(serviceDateStr, width: 110),
          SizedBox(
            width: 120,
            child: _StatusBadge(status: booking.status),
          ),
          SizedBox(
            width: 160,
            child: _ServicesCell(items: booking.items),
          ),
          _Cell(_currency.format(booking.subtotal),
              width: 90, align: TextAlign.right),
          _Cell(_currency.format(booking.discountAmount),
              width: 90, align: TextAlign.right),
          _Cell(
            _currency.format(booking.totalAmount),
            width: 100,
            align: TextAlign.right,
            bold: true,
          ),
          _Cell(createdStr, width: 110),
          SizedBox(
            width: 110,
            child: _ReviewStatusBadge(reviewed: booking.review != null),
          ),
          SizedBox(
            width: 110,
            child: booking.review != null
                ? _StarRating(rating: booking.review!.rating)
                : Text('—',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
          ),
          SizedBox(
            width: 110,
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
                  icon: Icon(Icons.edit_rounded,
                      size: 16, color: AppColors.accent),
                  tooltip: 'Edit',
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

// ── Reusable widgets ───────────────────────────────────────────────────────────

class _Cell extends StatelessWidget {
  final String text;
  final double width;
  final bool header;
  final bool bold;
  final TextAlign align;
  final Color? color;
  final String? tooltip;

  const _Cell(
    this.text, {
    required this.width,
    this.header = false,
    this.bold = false,
    this.align = TextAlign.left,
    this.color,
    this.tooltip,
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
            color: color ?? AppColors.textPrimary,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          );

    final textWidget = Text(
      text,
      style: style,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
    );

    return SizedBox(
      width: width,
      child: tooltip != null
          ? Tooltip(message: tooltip!, child: textWidget)
          : textWidget,
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

class _ReviewStatusBadge extends StatelessWidget {
  final bool reviewed;
  const _ReviewStatusBadge({required this.reviewed});

  @override
  Widget build(BuildContext context) {
    final color = reviewed
        ? const Color(0xFF38A169)
        : AppColors.textSecondary;
    final bg = reviewed
        ? const Color(0xFFF0FFF4)
        : AppColors.background;
    final label = reviewed ? 'Reviewed' : 'Not Reviewed';

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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
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

// ── Services cell for the table ───────────────────────────────────────────────

class _ServicesCell extends StatelessWidget {
  final List<BookingItem> items;
  const _ServicesCell({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text('—',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF8FF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${items.length} services',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3182CE),
                ),
              ),
            ),
          ),
        ...items.take(2).map(
              (item) => Text(
                item.serviceName.isNotEmpty ? item.serviceName : '—',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        if (items.length > 2)
          Text(
            '+${items.length - 2} more',
            style:
                TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
      ],
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

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
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
