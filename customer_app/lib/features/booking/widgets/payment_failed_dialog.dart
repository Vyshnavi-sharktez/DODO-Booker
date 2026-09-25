import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Shows a centered "Payment Failed" dialog for definitively failed or
/// dismissed Razorpay checkouts.
///
/// [onBackToCart] is invoked after the dialog is dismissed — callers should
/// use it to navigate the user back to wherever their cart is visible.
///
/// Do NOT use this for uncertain-payment outcomes (external wallet redirect,
/// HMAC verification error) — those are handled with a snackbar and a warning
/// banner in My Bookings, because the customer may already have been charged.
Future<void> showPaymentFailedDialog(
  BuildContext context, {
  required VoidCallback onBackToCart,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PaymentFailedDialog(onBackToCart: onBackToCart),
  );
}

class _PaymentFailedDialog extends StatelessWidget {
  final VoidCallback onBackToCart;

  const _PaymentFailedDialog({required this.onBackToCart});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.error.withAlpha(18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Payment Failed',
            style: tt.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Your items are still in your cart. '
          'You can try again whenever you\'re ready.',
          style: tt.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onBackToCart();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Back to Cart',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
