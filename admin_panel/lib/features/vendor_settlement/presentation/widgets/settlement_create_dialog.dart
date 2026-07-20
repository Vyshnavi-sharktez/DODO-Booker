import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../application/providers/vendor_settlement_providers.dart';
import '../../domain/models/vendor_booking_row.dart';
import '../../domain/models/vendor_earnings_summary.dart';

// ── Column widths (must match between header and data rows) ──────────────────

const double _colCheck = 52;
const double _colOrder = 96;
const double _colDate  = 82;
const double _colSvc   = 115;
const double _colTax   = 100;
const double _colPaid  = 115;
const double _colComm  = 135;
const double _colNet   = 125;
const double _colStatus = 80;
const double _tableMinWidth =
    _colCheck + _colOrder + _colDate + _colSvc + _colTax +
    _colPaid + _colComm + _colNet + _colStatus; // ≈ 900

class SettlementCreateDialog extends ConsumerStatefulWidget {
  const SettlementCreateDialog({super.key, required this.summary});
  final VendorEarningsSummary summary;

  @override
  ConsumerState<SettlementCreateDialog> createState() =>
      _SettlementCreateDialogState();
}

class _SettlementCreateDialogState
    extends ConsumerState<SettlementCreateDialog> {
  final _refCtrl   = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _paymentMethod = 'Bank Transfer';
  bool _saving = false;
  final _selected = <String>{};

  static final _fmt     = NumberFormat('#,##0.00', 'en_IN');
  static final _dateFmt = DateFormat('dd MMM yy');

  static const _paymentMethods = ['Bank Transfer', 'UPI', 'Cash', 'Cheque'];

  @override
  void dispose() {
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<VendorBookingRow> _unpaid(List<VendorBookingRow> all) =>
      all.where((r) => !r.isPaid).toList();

  double _selectedSubtotal(List<VendorBookingRow> unpaid) => unpaid
      .where((r) => _selected.contains(r.bookingId))
      .fold(0.0, (s, r) => s + r.subtotalBeforeTax);

  double _selectedCommission(List<VendorBookingRow> unpaid) => unpaid
      .where((r) => _selected.contains(r.bookingId))
      .fold(0.0, (s, r) => s + r.commissionAmount);

  double _selectedNet(List<VendorBookingRow> unpaid) => unpaid
      .where((r) => _selected.contains(r.bookingId))
      .fold(0.0, (s, r) => s + r.netVendorAmount);

  Future<void> _submit(List<VendorBookingRow> unpaid) async {
    final toSettle =
        unpaid.where((r) => _selected.contains(r.bookingId)).toList();
    if (toSettle.isEmpty) return;

    setState(() => _saving = true);
    try {
      final adminUser = ref.read(currentAdminUserProvider);
      if (adminUser == null) {
        throw Exception('Admin session expired. Please log in again.');
      }
      await ref
          .read(vendorSettlementNotifierProvider.notifier)
          .createSettlementBatch(
            vendorId: widget.summary.vendorId,
            vendorName: widget.summary.vendorName,
            bookings: toSettle,
            settledBy: adminUser.id,
            paymentMethod: _paymentMethod,
            referenceNumber:
                _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
            notes:
                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      if (mounted) {
        ref.invalidate(vendorBookingRowsProvider(widget.summary.vendorId));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payout failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync =
        ref.watch(vendorBookingRowsProvider(widget.summary.vendorId));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.payments_rounded,
                        color: AppColors.success, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pay Vendor Orders',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          widget.summary.vendorName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Helper note ─────────────────────────────────────────────────
              _InfoNote(
                'Platform Commission is calculated on the service amount before tax. '
                'Vendor Receivable = Service Amount − Commission.',
              ),
              const SizedBox(height: 10),
              const Divider(color: AppColors.border),

              // ── Booking list ────────────────────────────────────────────────
              Expanded(
                child: rowsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('Error loading orders: $e',
                        style: const TextStyle(color: AppColors.error)),
                  ),
                  data: (allRows) {
                    final unpaid = _unpaid(allRows);
                    if (unpaid.isEmpty) {
                      return const Center(
                        child: Text('No pending orders.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      );
                    }

                    return Column(
                      children: [
                        // Horizontally-scrollable table (header + rows)
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: _tableMinWidth,
                              child: Column(
                                children: [
                                  // Select-all header row
                                  _TableHeader(
                                    allSelected:
                                        _selected.length == unpaid.length &&
                                            unpaid.isNotEmpty,
                                    pendingCount: unpaid.length,
                                    onSelectAll: () => setState(() {
                                      if (_selected.length == unpaid.length) {
                                        _selected.clear();
                                      } else {
                                        _selected.addAll(
                                            unpaid.map((r) => r.bookingId));
                                      }
                                    }),
                                  ),
                                  const Divider(
                                      height: 1, color: AppColors.border),
                                  // Data rows
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: unpaid.length,
                                      itemBuilder: (_, i) {
                                        final row = unpaid[i];
                                        final checked = _selected
                                            .contains(row.bookingId);
                                        return _BookingSelectRow(
                                          row: row,
                                          checked: checked,
                                          fmt: _fmt,
                                          dateFmt: _dateFmt,
                                          onToggle: () => setState(() {
                                            if (checked) {
                                              _selected
                                                  .remove(row.bookingId);
                                            } else {
                                              _selected.add(row.bookingId);
                                            }
                                          }),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Summary strip (outside horizontal scroll)
                        if (_selected.isNotEmpty) ...[
                          const Divider(color: AppColors.border),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _TotalItem(
                                  label: 'Selected',
                                  value: _selected.length.toString(),
                                  color: AppColors.primary,
                                ),
                                _TotalItem(
                                  label: 'Service Amount',
                                  value:
                                      '₹${_fmt.format(_selectedSubtotal(unpaid))}',
                                  color: AppColors.textPrimary,
                                ),
                                _TotalItem(
                                  label: 'DODO Commission',
                                  value:
                                      '₹${_fmt.format(_selectedCommission(unpaid))}',
                                  color: AppColors.textSecondary,
                                ),
                                _TotalItem(
                                  label: 'Vendor Receivable',
                                  value:
                                      '₹${_fmt.format(_selectedNet(unpaid))}',
                                  color: AppColors.success,
                                  bold: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),

              const Divider(color: AppColors.border),
              const SizedBox(height: 14),

              // ── Payment fields ──────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment Method *',
                        prefixIcon:
                            Icon(Icons.account_balance_rounded, size: 18),
                        isDense: true,
                      ),
                      items: _paymentMethods
                          .map((m) =>
                              DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (v) => setState(() => _paymentMethod = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reference / Transaction No. (Optional)',
                        prefixIcon: Icon(Icons.tag_rounded, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  alignLabelWithHint: true,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 18),

              // ── Actions ─────────────────────────────────────────────────────
              rowsAsync.whenData((allRows) {
                final unpaid = _unpaid(allRows);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: (_saving || _selected.isEmpty)
                          ? null
                          : () => _submit(unpaid),
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _selected.isEmpty
                            ? 'Select orders to pay'
                            : 'Mark ${_selected.length} order${_selected.length == 1 ? '' : 's'} as Paid',
                      ),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success),
                    ),
                  ],
                );
              }).valueOrNull ??
                  const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Table header row ───────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    required this.allSelected,
    required this.pendingCount,
    required this.onSelectAll,
  });
  final bool allSelected;
  final int pendingCount;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Row(
        children: [
          SizedBox(
            width: _colCheck,
            child: Checkbox(
              value: allSelected,
              tristate: true,
              onChanged: (_) => onSelectAll(),
            ),
          ),
          _Col(_colOrder,  _hdr('Order ID')),
          _Col(_colDate,   _hdr('Date')),
          _Col(_colSvc,    _hdr('Service Amount')),
          _Col(_colTax,    _hdr('Tax')),
          _Col(_colPaid,   _hdrWithSub('Customer Paid', '(Inc. GST)')),
          _Col(_colComm,   _hdr('Platform Commission')),
          _Col(_colNet,    _hdr('Vendor Receivable')),
          SizedBox(
            width: _colStatus,
            child: Text(
              '$pendingCount pending',
              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _hdr(String label) => Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      );

  static Widget _hdrWithSub(String label, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
}

// ── Booking data row ───────────────────────────────────────────────────────────

class _BookingSelectRow extends StatelessWidget {
  const _BookingSelectRow({
    required this.row,
    required this.checked,
    required this.fmt,
    required this.dateFmt,
    required this.onToggle,
  });
  final VendorBookingRow row;
  final bool checked;
  final NumberFormat fmt;
  final DateFormat dateFmt;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        decoration: BoxDecoration(
          color: checked
              ? AppColors.success.withValues(alpha: 0.05)
              : Colors.transparent,
          border: const Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: _colCheck,
              child: Checkbox(value: checked, onChanged: (_) => onToggle()),
            ),
            // Order ID
            _Col(
              _colOrder,
              Text(
                '#${row.bookingId.length > 8 ? row.bookingId.substring(0, 8).toUpperCase() : row.bookingId.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            // Date
            _Col(
              _colDate,
              Text(dateFmt.format(row.completedAt),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
            // Service Amount Before Tax
            _Col(
              _colSvc,
              Text('₹${fmt.format(row.subtotalBeforeTax)}',
                  style: const TextStyle(fontSize: 13)),
            ),
            // Tax
            _Col(
              _colTax,
              row.hasTaxBreakdown
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₹${fmt.format(row.taxAmount)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        Text(
                          row.subtotalBeforeTax > 0
                              ? '${(row.taxAmount / row.subtotalBeforeTax * 100).toStringAsFixed(1)}%'
                              : '—',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ],
                    )
                  : const Text('—',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
            ),
            // Customer Paid
            _Col(
              _colPaid,
              Text('₹${fmt.format(row.bookingGross)}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
            // Commission (amount + rate on two lines)
            _Col(
              _colComm,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '₹${fmt.format(row.commissionAmount)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Text(
                    row.commissionLabel,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            // Vendor Receivable
            _Col(
              _colNet,
              Text(
                '₹${fmt.format(row.netVendorAmount)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ),
            // Payout Status (always Pending in this dialog)
            SizedBox(
              width: _colStatus,
              child: _PendingBadge(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared layout helper ───────────────────────────────────────────────────────

class _Col extends StatelessWidget {
  const _Col(this.width, this.child);
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      ),
    );
  }
}

// ── Pending status badge ───────────────────────────────────────────────────────

class _PendingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Pending',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.warning,
          ),
        ),
      ),
    );
  }
}

// ── Info note banner ───────────────────────────────────────────────────────────

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 13, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

// ── Summary total item ─────────────────────────────────────────────────────────

class _TotalItem extends StatelessWidget {
  const _TotalItem({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });
  final String label;
  final String value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
