import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Bottom sheet that lets the user pick a payment method before checkout.
/// Returns the selected payment method key (e.g. 'cash'), or null if dismissed.
class PaymentSelectionSheet extends StatefulWidget {
  const PaymentSelectionSheet({super.key});

  @override
  State<PaymentSelectionSheet> createState() => _PaymentSelectionSheetState();
}

class _PaymentSelectionSheetState extends State<PaymentSelectionSheet> {
  String _selected = 'cash';

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Select Payment Method',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          _PaymentOption(
            selected: _selected == 'cash',
            icon: Icons.payments_outlined,
            title: 'Cash After Service',
            subtitle: 'Pay with cash when your service is complete.',
            onTap: () => setState(() => _selected = 'cash'),
          ),
          const SizedBox(height: 12),
          _PaymentOption(
            selected: false,
            disabled: true,
            icon: Icons.credit_card_outlined,
            title: 'Pay Online',
            subtitle: 'Card, UPI, Net Banking.',
            badge: 'Coming Soon',
            onTap: null,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_selected),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  final bool selected;
  final bool disabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;

  const _PaymentOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.disabled = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1.0,
          ),
          color: selected ? AppColors.surfaceVariant : AppColors.surface,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: disabled
                  ? AppColors.textHint
                  : selected
                      ? AppColors.primary
                      : AppColors.textSecondary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: disabled
                                ? AppColors.textHint
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: tt.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  size: 20, color: AppColors.primary)
            else
              const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}
