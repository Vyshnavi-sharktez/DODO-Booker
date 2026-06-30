import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../application/providers/vendor_settlement_providers.dart';
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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _paymentMethod = 'Bank Transfer';
  bool _saving = false;

  static final _fmt = NumberFormat('#,##0.00', 'en_IN');

  static const _paymentMethods = [
    'Bank Transfer',
    'UPI',
    'Cash',
    'Cheque',
  ];

  @override
  void initState() {
    super.initState();
    final pending = widget.summary.pendingSettlement;
    _amountCtrl = TextEditingController(
      text: pending > 0 ? pending.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _parsedAmount => double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final adminUser = ref.read(currentAdminUserProvider);
      final s = widget.summary;
      await ref.read(vendorSettlementNotifierProvider.notifier).createSettlement(
            vendorId: s.vendorId,
            vendorName: s.vendorName,
            amount: _parsedAmount,
            completedJobsCount: s.completedJobs,
            settledBy: adminUser?.displayName ?? 'Admin',
            paymentMethod: _paymentMethod,
            referenceNumber:
                _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
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
    final s = widget.summary;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: AppColors.success,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mark as Paid',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            s.vendorName,
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
                const SizedBox(height: 20),

                // Summary strip
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _SummaryItem(
                            label: 'Completed Jobs',
                            value: s.completedJobs.toString(),
                            color: AppColors.primary,
                          ),
                          _Divider(),
                          _SummaryItem(
                            label: 'Gross Earnings',
                            value: '₹${_fmt.format(s.grossEarnings)}',
                            color: AppColors.textPrimary,
                          ),
                          _Divider(),
                          _SummaryItem(
                            label: 'Platform Commission',
                            value: '₹0.00',
                            color: AppColors.textSecondary,
                          ),
                          _Divider(),
                          _SummaryItem(
                            label: 'Adjustments',
                            value: '—',
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: AppColors.border),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _SummaryItem(
                            label: 'Previously Settled',
                            value: '₹${_fmt.format(s.totalSettled)}',
                            color: AppColors.textSecondary,
                          ),
                          _Divider(),
                          _SummaryItem(
                            label: 'Final Payable Amount',
                            value: '₹${_fmt.format(s.pendingSettlement)}',
                            color: AppColors.warning,
                            bold: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Amount field
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Settlement Amount (₹) *',
                    prefixIcon: Icon(Icons.currency_rupee_rounded, size: 18),
                    helperText: 'Defaults to full pending amount; edit for partial',
                  ),
                  validator: (v) {
                    final val = double.tryParse(v?.trim() ?? '');
                    if (val == null || val <= 0) {
                      return 'Enter a valid amount greater than zero';
                    }
                    if (val > s.pendingSettlement + 0.01) {
                      return 'Exceeds pending settlement (₹${_fmt.format(s.pendingSettlement)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Payment Method
                // ignore: deprecated_member_use
                DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method *',
                    prefixIcon: Icon(Icons.account_balance_rounded, size: 18),
                  ),
                  items: _paymentMethods
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(() => _paymentMethod = v),
                  validator: (v) =>
                      v == null ? 'Select a payment method' : null,
                ),
                const SizedBox(height: 16),

                // Reference Number
                TextFormField(
                  controller: _refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reference / Transaction Number (Optional)',
                    prefixIcon: Icon(Icons.tag_rounded, size: 18),
                  ),
                ),
                const SizedBox(height: 16),

                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 28),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Mark as Paid'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
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
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
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

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: AppColors.border,
    );
  }
}
