import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../application/providers/vendor_settlement_providers.dart';
import '../../domain/models/vendor_booking_row.dart';
import '../../domain/models/vendor_earnings_summary.dart';

class SettlementCreateDialog extends ConsumerStatefulWidget {
  const SettlementCreateDialog({super.key, required this.summary});
  final VendorEarningsSummary summary;

  @override
  ConsumerState<SettlementCreateDialog> createState() =>
      _SettlementCreateDialogState();
}

class _SettlementCreateDialogState
    extends ConsumerState<SettlementCreateDialog> {
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _paymentMethod = 'Bank Transfer';
  bool _saving = false;
  final _selected = <String>{};

  static final _fmt = NumberFormat('#,##0.00', 'en_IN');
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

  double _selectedGross(List<VendorBookingRow> unpaid) => unpaid
      .where((r) => _selected.contains(r.bookingId))
      .fold(0.0, (s, r) => s + r.bookingGross);

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
        ref.invalidate(
            vendorBookingRowsProvider(widget.summary.vendorId));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settlement failed: $e'),
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
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────────
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
                          'Settle Orders',
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
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),

              // ── Booking list ─────────────────────────────────────────────────
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
                        child: Text(
                          'No pending orders to settle.',
                          style:
                              TextStyle(color: AppColors.textSecondary),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        // Select-all row
                        Row(
                          children: [
                            Checkbox(
                              value: _selected.length == unpaid.length &&
                                  unpaid.isNotEmpty,
                              tristate: true,
                              onChanged: (_) {
                                setState(() {
                                  if (_selected.length == unpaid.length) {
                                    _selected.clear();
                                  } else {
                                    _selected.addAll(
                                        unpaid.map((r) => r.bookingId));
                                  }
                                });
                              },
                            ),
                            const Text(
                              'Select All',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${unpaid.length} pending order${unpaid.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 1, color: AppColors.border),

                        // Booking rows
                        Expanded(
                          child: ListView.builder(
                            itemCount: unpaid.length,
                            itemBuilder: (_, i) {
                              final row = unpaid[i];
                              final isChecked =
                                  _selected.contains(row.bookingId);
                              return _BookingSelectRow(
                                row: row,
                                checked: isChecked,
                                fmt: _fmt,
                                dateFmt: _dateFmt,
                                onToggle: () => setState(() {
                                  if (isChecked) {
                                    _selected.remove(row.bookingId);
                                  } else {
                                    _selected.add(row.bookingId);
                                  }
                                }),
                              );
                            },
                          ),
                        ),

                        // Selected totals strip
                        if (_selected.isNotEmpty) ...[
                          const Divider(color: AppColors.border),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceAround,
                              children: [
                                _TotalItem(
                                  label: 'Selected Orders',
                                  value: _selected.length.toString(),
                                  color: AppColors.primary,
                                ),
                                _TotalItem(
                                  label: 'Gross',
                                  value:
                                      '₹${_fmt.format(_selectedGross(unpaid))}',
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

              // ── Payment fields ───────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment Method *',
                        prefixIcon: Icon(
                            Icons.account_balance_rounded,
                            size: 18),
                        isDense: true,
                      ),
                      items: _paymentMethods
                          .map((m) =>
                              DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _paymentMethod = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Reference / Transaction No. (Optional)',
                        prefixIcon:
                            Icon(Icons.tag_rounded, size: 18),
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

              // ── Actions ──────────────────────────────────────────────────────
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
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _selected.isEmpty
                            ? 'Select orders to settle'
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

// ── Booking row widget ─────────────────────────────────────────────────────────

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
            bottom: BorderSide(color: AppColors.border, width: 0.5),
          ),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Checkbox(value: checked, onChanged: (_) => onToggle()),
            const SizedBox(width: 4),
            Expanded(
              flex: 2,
              child: Text(
                '#${row.bookingId.length > 8 ? row.bookingId.substring(0, 8).toUpperCase() : row.bookingId.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                dateFmt.format(row.completedAt),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '₹${fmt.format(row.bookingGross)}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
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
            Expanded(
              flex: 2,
              child: Text(
                '₹${fmt.format(row.netVendorAmount)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
        ),
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
