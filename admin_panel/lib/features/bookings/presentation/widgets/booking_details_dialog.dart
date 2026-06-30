import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../dodo_teams/application/providers/dodo_teams_providers.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/booking_item.dart';

const _statusConfig = <String, (String, Color, Color)>{
  'pending':     ('Pending',     Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'assigned':    ('Assigned',    Color(0xFF3182CE), Color(0xFFEBF8FF)),
  'accepted':    ('Accepted',    Color(0xFF2C7A7B), Color(0xFFE6FFFA)),
  'on_the_way':  ('On The Way',  Color(0xFF4A6FA5), Color(0xFFEBF4FF)),
  'arrived':     ('Arrived',     Color(0xFF6B46C1), Color(0xFFF3E8FF)),
  'in_progress': ('In Progress', Color(0xFF805AD5), Color(0xFFFAF5FF)),
  'completed':   ('Completed',   Color(0xFF38A169), Color(0xFFF0FFF4)),
  'rejected':    ('Rejected',    Color(0xFFC05621), Color(0xFFFEEBC8)),
  'cancelled':   ('Cancelled',   Color(0xFFE53E3E), Color(0xFFFFF5F5)),
};

const _cancellableStatuses = {
  'pending', 'assigned', 'accepted', 'on_the_way', 'arrived', 'in_progress',
};

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('dd MMM yyyy');

class BookingDetailsDialog extends ConsumerWidget {
  final Booking booking;
  final VoidCallback? onAssign;
  final VoidCallback? onCancel;

  const BookingDetailsDialog({
    super.key,
    required this.booking,
    this.onAssign,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
    final teams = ref.watch(dodoTeamsNotifierProvider).valueOrNull ?? [];
    final vendor = vendors.where((v) => v.id == booking.vendorId).firstOrNull;
    final team = teams.where((t) => t.id == booking.dodoTeamId).firstOrNull;

    final assignedToLabel = switch (booking.assignmentType) {
      'External Vendor' =>
        vendor?.businessName ?? _truncateId(booking.vendorId),
      'DODO Team' => team?.teamName ?? _truncateId(booking.dodoTeamId),
      _ => 'Unassigned',
    };

    final statusCfg = _statusConfig[booking.status];
    final statusLabel = statusCfg?.$1 ?? booking.status;
    final statusColor = statusCfg?.$2 ?? AppColors.textSecondary;
    final statusBg = statusCfg?.$3 ?? AppColors.background;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Booking #${booking.bookingNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // ── Content ───────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel('Booking Info'),
                    const SizedBox(height: 12),
                    _InfoRow('Booking Number', booking.bookingNumber),
                    _InfoRow('Customer ID', _truncateId(booking.customerId),
                        tooltip: booking.customerId),
                    _InfoRow('Assignment Type', booking.assignmentType),
                    _InfoRow('Assigned To', assignedToLabel),
                    _InfoRow(
                      'Service Date',
                      booking.serviceDate != null
                          ? _dateFmt.format(booking.serviceDate!)
                          : '—',
                    ),
                    _InfoRow('Status', statusLabel),
                    if (booking.address != null &&
                        booking.address!.isNotEmpty)
                      _InfoRow('Address', booking.address!),
                    if (booking.notes != null && booking.notes!.isNotEmpty)
                      _InfoRow('Notes', booking.notes!),
                    const SizedBox(height: 20),

                    if (booking.items.isNotEmpty) ...[
                      _SectionLabel(
                          'Services (${booking.items.length})'),
                      const SizedBox(height: 12),
                      ...booking.items.map((item) =>
                          _ServiceItemRow(item: item, currency: _currency)),
                      const SizedBox(height: 20),
                    ],

                    _SectionLabel('Financials'),
                    const SizedBox(height: 12),
                    _InfoRow('Subtotal', _currency.format(booking.subtotal)),
                    _InfoRow('Discount',
                        _currency.format(booking.discountAmount)),
                    const Divider(height: 16),
                    _InfoRow(
                      'Total Amount',
                      _currency.format(booking.totalAmount),
                      bold: true,
                    ),
                    const SizedBox(height: 20),

                    _SectionLabel('Timestamps'),
                    const SizedBox(height: 12),
                    _InfoRow(
                      'Created',
                      booking.createdAt != null
                          ? DateFormat('dd MMM yyyy, hh:mm a')
                              .format(booking.createdAt!)
                          : '—',
                    ),
                    _InfoRow(
                      'Updated',
                      booking.updatedAt != null
                          ? DateFormat('dd MMM yyyy, hh:mm a')
                              .format(booking.updatedAt!)
                          : '—',
                    ),
                    const SizedBox(height: 20),

                    _SectionLabel('Review'),
                    const SizedBox(height: 12),
                    if (booking.review != null) ...[
                      _InfoRow(
                        'Rating',
                        '${booking.review!.rating} / 5',
                      ),
                      _StarRatingRow(rating: booking.review!.rating),
                      const SizedBox(height: 8),
                      _InfoRow('Review Text', booking.review!.reviewText),
                      _InfoRow(
                        'Submitted',
                        booking.review!.createdAt != null
                            ? DateFormat('dd MMM yyyy, hh:mm a')
                                .format(booking.review!.createdAt!)
                            : '—',
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'No review submitted',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Footer ────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  if (onCancel != null &&
                      _cancellableStatuses.contains(booking.status))
                    OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel Booking'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  const Spacer(),
                  if (onAssign != null)
                    FilledButton.icon(
                      onPressed: onAssign,
                      icon: Icon(
                        booking.isUnassigned
                            ? Icons.assignment_ind_rounded
                            : Icons.swap_horiz_rounded,
                        size: 16,
                      ),
                      label: Text(
                        booking.isUnassigned ? 'Assign' : 'Reassign',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  if (onAssign != null) const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _truncateId(String id) {
  if (id.length <= 8) return id;
  return '${id.substring(0, 8)}…';
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _StarRatingRow extends StatelessWidget {
  final int rating;
  const _StarRatingRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              'Stars',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (i) {
              return Icon(
                i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 18,
                color: i < rating
                    ? const Color(0xFFD69E2E)
                    : AppColors.textSecondary.withValues(alpha: 0.3),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _ServiceItemRow extends StatelessWidget {
  final BookingItem item;
  final NumberFormat currency;

  const _ServiceItemRow({required this.item, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 130,
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 14, color: Color(0xFF38A169)),
                SizedBox(width: 6),
              ],
            ),
          ),
          Expanded(
            child: Text(
              item.serviceName.isNotEmpty ? item.serviceName : '—',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.format(item.totalPrice),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (item.quantity > 1)
                Text(
                  '${item.quantity} × ${currency.format(item.unitPrice)}',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final String? tooltip;

  const _InfoRow(this.label, this.value,
      {this.bold = false, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final valueWidget = Text(
      value,
      style: TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: tooltip != null
                ? Tooltip(message: tooltip!, child: valueWidget)
                : valueWidget,
          ),
        ],
      ),
    );
  }
}
