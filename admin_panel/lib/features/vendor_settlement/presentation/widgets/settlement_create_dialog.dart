import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/application/providers/auth_provider.dart';
import '../../../../features/vendors/application/providers/vendors_providers.dart';
import '../../../../features/vendors/domain/models/vendor.dart';
import '../../application/providers/vendor_settlement_providers.dart';
import '../../domain/models/vendor_settlement.dart';

class SettlementCreateDialog extends ConsumerStatefulWidget {
  const SettlementCreateDialog({super.key, required this.vendor});
  final Vendor vendor;

  @override
  ConsumerState<SettlementCreateDialog> createState() =>
      _SettlementCreateDialogState();
}

class _SettlementCreateDialogState
    extends ConsumerState<SettlementCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  static final _fmt = NumberFormat('#,##0.00', 'en_IN');

  double get _parsedAmount =>
      double.tryParse(_amountCtrl.text.trim()) ?? 0.0;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final vendor = widget.vendor;
      final amount = _parsedAmount;
      final newBalance = vendor.walletBalance - amount;
      final adminUser = ref.read(currentAdminUserProvider);

      await ref.read(vendorSettlementRepositoryProvider).deductWalletBalance(
            vendor.id,
            newBalance: newBalance,
          );

      final entry = VendorSettlement(
        id: '${vendor.id}_${DateTime.now().millisecondsSinceEpoch}',
        vendorId: vendor.id,
        vendorName: vendor.businessName,
        amount: amount,
        balanceBefore: vendor.walletBalance,
        balanceAfter: newBalance,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        settledAt: DateTime.now(),
        settledBy: adminUser?.displayName ?? 'Admin',
      );
      ref.read(vendorSettlementHistoryProvider.notifier).addEntry(entry);
      await ref.read(vendorsNotifierProvider.notifier).refresh();

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
    final vendor = widget.vendor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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
                        Icons.account_balance_wallet_rounded,
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
                            'Process Settlement',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            vendor.businessName,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Balance preview
                AnimatedBuilder(
                  animation: _amountCtrl,
                  builder: (context, _) {
                    final amount = _parsedAmount;
                    final isValid =
                        amount > 0 && amount <= vendor.walletBalance;
                    final balanceAfter =
                        (vendor.walletBalance - amount).clamp(0.0, double.infinity);

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _BalanceColumn(
                            label: 'Current Balance',
                            value: '₹${_fmt.format(vendor.walletBalance)}',
                            valueColor: vendor.walletBalance > 0
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                          _BalanceColumn(
                            label: 'After Settlement',
                            value: isValid
                                ? '₹${_fmt.format(balanceAfter)}'
                                : '—',
                            valueColor: isValid
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ],
                      ),
                    );
                  },
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
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final val = double.tryParse(v?.trim() ?? '');
                    if (val == null || val <= 0) {
                      return 'Enter a valid amount greater than zero';
                    }
                    if (val > vendor.walletBalance) {
                      return 'Exceeds wallet balance (₹${_fmt.format(vendor.walletBalance)})';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Notes field
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
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
                      label: const Text('Process Settlement'),
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

class _BalanceColumn extends StatelessWidget {
  const _BalanceColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
