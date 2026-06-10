import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vendors/application/providers/vendors_providers.dart';
import '../../domain/models/booking.dart';

const _statusConfig = <String, (String, Color, Color)>{
  'pending': ('Pending', Color(0xFFDD6B20), Color(0xFFFEEBC8)),
  'assigned': ('Assigned', Color(0xFF3182CE), Color(0xFFEBF8FF)),
  'in_progress': ('In Progress', Color(0xFF805AD5), Color(0xFFFAF5FF)),
  'completed': ('Completed', Color(0xFF38A169), Color(0xFFF0FFF4)),
  'cancelled': ('Cancelled', Color(0xFFE53E3E), Color(0xFFFFF5F5)),
};

final _currency = NumberFormat.currency(symbol: '₹', decimalDigits: 2);
final _dateFmt = DateFormat('dd MMM yyyy');

class BookingDetailsDialog extends ConsumerWidget {
  final Booking booking;

  const BookingDetailsDialog({super.key, required this.booking});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(vendorsNotifierProvider).valueOrNull ?? [];
    final vendor = vendors.where((v) => v.id == booking.vendorId).firstOrNull;
    final vendorLabel = vendor?.businessName ?? _truncateId(booking.vendorId);

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
                    _InfoRow('Vendor', vendorLabel,
                        tooltip: booking.vendorId),
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
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Close'),
                ),
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
