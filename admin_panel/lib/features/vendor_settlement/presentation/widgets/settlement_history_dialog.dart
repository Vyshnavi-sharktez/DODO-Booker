import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../application/providers/vendor_settlement_providers.dart';
import '../../domain/models/vendor_booking_row.dart';

enum _OrderFilter { all, pending, paid }

class SettlementHistoryDialog extends ConsumerStatefulWidget {
  const SettlementHistoryDialog({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });
  final String vendorId;
  final String vendorName;

  @override
  ConsumerState<SettlementHistoryDialog> createState() =>
      _SettlementHistoryDialogState();
}

class _SettlementHistoryDialogState
    extends ConsumerState<SettlementHistoryDialog> {
  _OrderFilter _filter = _OrderFilter.all;

  static final _dateFmt  = DateFormat('dd MMM yyyy');
  static final _moneyFmt = NumberFormat('#,##0.00', 'en_IN');

  List<VendorBookingRow> _applyFilter(List<VendorBookingRow> rows) {
    return switch (_filter) {
      _OrderFilter.all     => rows,
      _OrderFilter.pending => rows.where((r) => !r.isPaid).toList(),
      _OrderFilter.paid    => rows.where((r) => r.isPaid).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(vendorBookingRowsProvider(widget.vendorId));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────────────
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
                          widget.vendorName,
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
              const SizedBox(height: 14),
              const Divider(color: AppColors.border),
              const SizedBox(height: 10),

              // ── Body (loading / error / data) ────────────────────────────────
              Expanded(
                child: rowsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('Error loading orders: $e',
                        style: const TextStyle(color: AppColors.error)),
                  ),
                  data: (allRows) {
                    if (allRows.isEmpty) {
                      return const Center(
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
                      );
                    }

                    final pendingCount =
                        allRows.where((r) => !r.isPaid).length;
                    final paidCount = allRows.where((r) => r.isPaid).length;
                    final filtered = _applyFilter(allRows);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Filter tabs ────────────────────────────────────────
                        Row(
                          children: [
                            _FilterTab(
                              label: 'All Orders',
                              count: allRows.length,
                              selected: _filter == _OrderFilter.all,
                              onTap: () => setState(
                                  () => _filter = _OrderFilter.all),
                            ),
                            const SizedBox(width: 8),
                            _FilterTab(
                              label: 'Pending',
                              count: pendingCount,
                              selected: _filter == _OrderFilter.pending,
                              color: AppColors.warning,
                              onTap: () => setState(
                                  () => _filter = _OrderFilter.pending),
                            ),
                            const SizedBox(width: 8),
                            _FilterTab(
                              label: 'Paid',
                              count: paidCount,
                              selected: _filter == _OrderFilter.paid,
                              color: AppColors.success,
                              onTap: () => setState(
                                  () => _filter = _OrderFilter.paid),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // ── Table ──────────────────────────────────────────────
                        if (filtered.isEmpty)
                          Expanded(
                            child: Center(
                              child: Text(
                                switch (_filter) {
                                  _OrderFilter.pending =>
                                    'No pending orders for this vendor.',
                                  _OrderFilter.paid =>
                                    'No paid orders for this vendor.',
                                  _OrderFilter.all =>
                                    'No orders found.',
                                },
                                style: const TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: LayoutBuilder(
                              builder: (ctx, constraints) {
                                final tableWidth =
                                    constraints.maxWidth > 1100.0
                                        ? constraints.maxWidth
                                        : 1100.0;
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: tableWidth,
                                    child: SingleChildScrollView(
                                      child: Table(
                                        columnWidths: const {
                                          0: FixedColumnWidth(110), // Order ID
                                          1: FixedColumnWidth(95),  // Completed
                                          2: FlexColumnWidth(1.6),  // Service Amount
                                          3: FlexColumnWidth(1.3),  // Tax
                                          4: FlexColumnWidth(1.5),  // Customer Paid
                                          5: FlexColumnWidth(1.6),  // Commission
                                          6: FixedColumnWidth(95),  // Rate
                                          7: FlexColumnWidth(1.6),  // Vendor Receivable
                                          8: FixedColumnWidth(75),  // Status
                                          9: FlexColumnWidth(1.8),  // Payout Ref
                                          10: FlexColumnWidth(1.4), // Payout Date
                                        },
                                        children: [
                                          TableRow(
                                            decoration: BoxDecoration(
                                              color: AppColors.background,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            children: const [
                                              _HeaderCell('Order ID'),
                                              _HeaderCell('Completed'),
                                              _HeaderCell('Service Amount'),
                                              _HeaderCell('Tax'),
                                              _HeaderCell('Customer Paid', subtitle: '(Inc. GST)'),
                                              _HeaderCell('Platform Commission'),
                                              _HeaderCell('Commission Rate'),
                                              _HeaderCell('Vendor Receivable'),
                                              _HeaderCell('Status'),
                                              _HeaderCell('Payout Ref'),
                                              _HeaderCell('Payout Date'),
                                            ],
                                          ),
                                          for (final row in filtered)
                                            _buildRow(row),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // ── Footer ──────────────────────────────────────────────────────
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 13, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text(
                      'Platform Commission is calculated on the service amount before tax.'
                      '  Vendor Receivable = Service Amount − Commission.',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
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

  static TableRow _buildRow(VendorBookingRow row) {
    final legacy = !row.hasTaxBreakdown;

    return TableRow(
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      children: [
        // Order ID
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
        // Completed
        _DataCell(
          child: Text(
            _dateFmt.format(row.completedAt),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        // Service Amount Before Tax
        _DataCell(
          child: legacy
              ? const Text('—',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary))
              : Text(
                  '₹${_moneyFmt.format(row.subtotalBeforeTax)}',
                  style: const TextStyle(fontSize: 13),
                ),
        ),
        // Tax (amount + rate)
        _DataCell(
          child: legacy
              ? const Text('—',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₹${_moneyFmt.format(row.taxAmount)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    Text(
                      row.subtotalBeforeTax > 0
                          ? '${(row.taxAmount / row.subtotalBeforeTax * 100).toStringAsFixed(1)}%'
                          : '—',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
        ),
        // Customer Paid
        _DataCell(
          child: Text(
            '₹${_moneyFmt.format(row.bookingGross)}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        // Platform Commission amount
        _DataCell(
          child: Text(
            '₹${_moneyFmt.format(row.commissionAmount)}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        // Commission rate label
        _DataCell(
          child: Text(
            row.commissionLabel,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        // Vendor Receivable
        _DataCell(
          child: Text(
            '₹${_moneyFmt.format(row.netVendorAmount)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ),
        // Status
        _DataCell(child: _StatusBadge(isPaid: row.isPaid)),
        // Payout Ref
        _DataCell(
          child: Text(
            row.referenceNumber ?? '—',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Payout Date
        _DataCell(
          child: Text(
            row.settledAt != null
                ? _dateFmt.format(row.settledAt!)
                : '—',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ── Filter tab chip ────────────────────────────────────────────────────────────

class _FilterTab extends StatelessWidget {
  const _FilterTab({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? effectiveColor.withValues(alpha: 0.12)
              : AppColors.background,
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
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? effectiveColor : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? effectiveColor.withValues(alpha: 0.15)
                    : AppColors.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? effectiveColor
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
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
  const _HeaderCell(this.text, {this.subtitle});
  final String text;
  final String? subtitle;

  static const _mainStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );
  static const _subStyle = TextStyle(
    fontSize: 9,
    color: AppColors.textSecondary,
    fontStyle: FontStyle.italic,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: subtitle == null
          ? Text(text, style: _mainStyle)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, style: _mainStyle),
                Text(subtitle!, style: _subStyle),
              ],
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
