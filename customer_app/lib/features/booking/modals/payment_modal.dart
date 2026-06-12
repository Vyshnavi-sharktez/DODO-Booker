import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';

/// Payment modal. Pops with `true` when the user confirms payment.
class PaymentModal extends StatelessWidget {
  final double totalAmount;

  const PaymentModal({super.key, required this.totalAmount});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return AppModalDialog(
      title: 'Payment',
      subtitle: const Text('Choose a payment method'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),

          // Amount due
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Amount Due',
                  style: tt.labelMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '₹${totalAmount.toStringAsFixed(2)}',
                  style: tt.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Payment options (placeholder)
          _PaymentOption(
            icon: Icons.account_balance_wallet_rounded,
            label: 'UPI / QR Code',
            tag: 'Recommended',
          ),
          const SizedBox(height: 10),
          _PaymentOption(
            icon: Icons.credit_card_rounded,
            label: 'Credit / Debit Card',
          ),
          const SizedBox(height: 10),
          _PaymentOption(
            icon: Icons.account_balance_rounded,
            label: 'Net Banking',
          ),
          const SizedBox(height: 10),
          _PaymentOption(
            icon: Icons.money_rounded,
            label: 'Cash on Service',
          ),

          const SizedBox(height: 20),

          // Coming soon banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Payment gateway integration is coming soon. '
                    'Tap below to confirm a test booking.',
                    style: tt.labelSmall?.copyWith(color: const Color(0xFFB45309)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(
              'Pay ₹${totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tag;

  const _PaymentOption({required this.icon, required this.label, this.tag});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            if (tag != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tag!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}
