import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Bottom sheet that lets the user pick a payment method before checkout.
/// Returns the selected payment method key (e.g. 'cash'), or null if dismissed.
class PaymentSelectionSheet extends StatefulWidget {
  const PaymentSelectionSheet({super.key, this.isAmc = false});

  final bool isAmc;

  @override
  State<PaymentSelectionSheet> createState() => _PaymentSelectionSheetState();
}

class _PaymentSelectionSheetState extends State<PaymentSelectionSheet> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.isAmc ? 'online' : 'cash';
  }

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
            disabled: widget.isAmc,
            disabledReason: widget.isAmc ? 'Not available for AMC bookings.' : null,
            onTap: widget.isAmc ? null : () => setState(() => _selected = 'cash'),
          ),
          const SizedBox(height: 12),
          _PaymentOption(
            selected: _selected == 'online',
            icon: Icons.credit_card_outlined,
            title: 'Pay Online',
            subtitle: 'Card, UPI, Net Banking.',
            onTap: () => setState(() => _selected = 'online'),
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
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool disabled;
  final String? disabledReason;

  const _PaymentOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.disabled = false,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final iconColor =
        disabled ? AppColors.textHint : (selected ? AppColors.primary : AppColors.textSecondary);
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: disabled ? AppColors.border : (selected ? AppColors.primary : AppColors.border),
            width: selected && !disabled ? 1.5 : 1.0,
          ),
          color: disabled
              ? AppColors.surface
              : (selected ? AppColors.surfaceVariant : AppColors.surface),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: disabled ? AppColors.textHint : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: tt.bodySmall?.copyWith(color: AppColors.textHint),
                  ),
                  if (disabledReason != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      disabledReason!,
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (selected && !disabled)
              const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.primary)
            else
              const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}
