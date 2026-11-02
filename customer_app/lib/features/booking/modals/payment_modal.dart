import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../providers/dodo_upi_provider.dart';
import 'upi_payment_modal.dart';

// ── Payment modal ─────────────────────────────────────────────────────────────
/// Pops with: `'razorpay'`, `'cod'`, `'upi_dodo'`, or `'upi_dodo:<utr>'`.

class PaymentModal extends ConsumerWidget {
  final double totalAmount;

  const PaymentModal({super.key, required this.totalAmount});

  Future<void> _openUpiModal(
    BuildContext context,
    DodoUpiConfig cfg,
  ) async {
    final result = await AppModalDialog.show<String>(
      context: context,
      child: UpiPaymentModal(
        upiId: cfg.upiId,
        qrImageUrl: cfg.qrImageUrl,
        totalAmount: totalAmount,
      ),
    );
    if (result != null && context.mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final upiCfgAsync = ref.watch(dodoUpiConfigProvider);

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

          _PaymentOption(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Pay Online',
            subtitle: 'UPI, Cards, Net Banking & more',
            tag: 'Recommended',
            onTap: () => Navigator.of(context).pop('razorpay'),
          ),

          // DODO UPI option — shown only when enabled and configured
          upiCfgAsync.when(
            data: (cfg) {
              if (cfg == null || !cfg.isEnabled) return const SizedBox.shrink();
              return Column(
                children: [
                  const SizedBox(height: 10),
                  _PaymentOption(
                    icon: Icons.qr_code_rounded,
                    label: 'Pay via DODO UPI',
                    subtitle: 'Scan QR or pay to our UPI ID directly',
                    onTap: () => _openUpiModal(context, cfg),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 10),
          _PaymentOption(
            icon: Icons.money_rounded,
            label: 'Cash After Service',
            subtitle: 'Pay when the service is done',
            onTap: () => Navigator.of(context).pop('cod'),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final String? tag;
  final VoidCallback onTap;

  const _PaymentOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: tt.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (tag != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            ],
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
