import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendor_settlement_providers.dart';
import '../../domain/models/vendor_booking_row.dart';

class SettlementHistoryDialog extends ConsumerWidget {
  const SettlementHistoryDialog({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });
  final String vendorId;
  final String vendorName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(vendorBookingRowsProvider(vendorId));
    final dateFmt = DateFormat('dd MMM yyyy');
    final moneyFmt = NumberFormat('#,##0.00', 'en_IN');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 580),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Order History',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          vendorName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),

              rowsAsync.when(
                loading: () => const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Expanded(
                  child: Center(
                    child: Text('Error loading orders: $e',
                        style: const TextStyle(color: AppColors.error)),
                  ),
                ),
                data: (rows) {
                  if (rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_rounded,
                                size: 40, color: AppColors.border),
                            SizedBox(height: 12),
                            Text('No completed orders found',
                                style: TextStyle(
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  }

                  return Expanded(
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final tableWidth = constraints.maxWidth > 820.0
                            ? constraints.maxWidth
                            : 820.0;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            child: SingleChildScrollView(
                              child: Table(
                                columnWidths: const {
                                  0: FixedColumnWidth(110),
                                  1: FixedColumnWidth(100),
                                  2: FlexColumnWidth(1.6),
                                  3: FlexColumnWidth(1.6),
                                  4: FlexColumnWidth(1.6),
                                  5: FlexColumnWidth(1.6),
                                  6: FixedColumnWidth(90),
                                  7: FlexColumnWidth(1.8),
                                  8: FlexColumnWidth(1.6),
                                },
                                children: [
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    children: const [
                                      _HeaderCell('Booking ID'),
                                      _HeaderCell('Completed'),
                                      _HeaderCell('Order Amount'),
                                      _HeaderCell('DODO Commission'),
                                      _HeaderCell('Commission Rate'),
                                      _HeaderCell('Vendor Receivable'),
                                      _HeaderCell('Status'),
                                      _HeaderCell('Settlement Ref'),
                                      _HeaderCell('Settled On'),
                                    ],
                                  ),
                                  for (final row in rows)
                                    _buildRow(row, moneyFmt, dateFmt),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _buildRow(
    VendorBookingRow row,
    NumberFormat moneyFmt,
    DateFormat dateFmt,
  ) {
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      children: [
        _DataCell(
          child: Text(
            '#${row.bookingId.length > 8 ? row.bookingId.substring(0, 8).toUpperCase() : row.bookingId.toUpperCase()}',
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: AppColors.textSecondary,
            ),
          ),
        ),
        _DataCell(
          child: Text(
            dateFmt.format(row.completedAt),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        _DataCell(
          child: Text(
            '₹${moneyFmt.format(row.bookingGross)}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        _DataCell(
          child: Text(
            '₹${moneyFmt.format(row.commissionAmount)}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        _DataCell(
          child: Text(
            row.commissionLabel,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        _DataCell(
          child: Text(
            '₹${moneyFmt.format(row.netVendorAmount)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ),
        _DataCell(
          child: _StatusBadge(isPaid: row.isPaid),
        ),
        _DataCell(
          child: Text(
            row.referenceNumber ?? '—',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _DataCell(
          child: Text(
            row.settledAt != null ? dateFmt.format(row.settledAt!) : '—',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isPaid});
  final bool isPaid;

  @override
  Widget build(BuildContext context) {
    final color = isPaid ? AppColors.success : AppColors.warning;
    final label = isPaid ? 'Paid' : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Table helpers ──────────────────────────────────────────────────────────────

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: child,
    );
  }
}
