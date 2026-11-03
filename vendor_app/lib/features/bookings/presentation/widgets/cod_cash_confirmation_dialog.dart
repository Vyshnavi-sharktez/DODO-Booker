import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// Shown after OTP verification for vendor-collected bookings.
/// Vendor selects HOW the customer paid: Cash or DODO Scanner (UPI).
/// Returns 'cash' or 'upi_dodo', or null when dismissed.
class CodCashConfirmationDialog extends StatefulWidget {
  const CodCashConfirmationDialog({
    super.key,
    required this.bookingNumber,
    required this.totalAmount,
  });

  final String bookingNumber;
  final double totalAmount;

  @override
  State<CodCashConfirmationDialog> createState() =>
      _CodCashConfirmationDialogState();
}

class _CodCashConfirmationDialogState extends State<CodCashConfirmationDialog> {
  String? _selected; // 'cash' | 'upi_dodo'

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 360,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.payments_rounded,
                          color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Confirm Collection',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Booking #${widget.bookingNumber}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Amount ───────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Amount Collected:',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(
                        '₹${widget.totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Payment mode selection ────────────────────────────────────
                const Text(
                  'How did the customer pay?',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ModeCard(
                          icon: Icons.money_rounded,
                          label: 'Cash',
                          selected: _selected == 'cash',
                          onTap: () => setState(() => _selected = 'cash'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ModeCard(
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'Scanner',
                          sublabel: 'DODO UPI',
                          selected: _selected == 'upi_dodo',
                          onTap: () => setState(() => _selected = 'upi_dodo'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Buttons ──────────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _selected == null
                            ? null
                            : () => Navigator.of(context).pop(_selected),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: const Text('Confirm'),
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sublabel,
  });

  final IconData icon;
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 28,
                color: selected ? AppColors.primary : Colors.grey.shade500),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : Colors.grey.shade700,
              ),
            ),
            if (sublabel != null) ...[
              const SizedBox(height: 2),
              Text(
                sublabel!,
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
