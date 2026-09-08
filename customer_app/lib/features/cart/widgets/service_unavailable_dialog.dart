import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Shows a centered modal informing the customer that one or more services
/// have been deactivated and removed from their cart.
///
/// Mirrors the layout of [showServiceAreaUnavailableDialog] so the UX is
/// consistent across all "cannot book" blocking dialogs in the customer app.
///
/// [serviceNames] — display names of every removed service (plain strings,
/// no wrapping quotes). The dialog formats them appropriately.
Future<void> showServiceUnavailableDialog(
  BuildContext context, {
  required List<String> serviceNames,
}) {
  assert(serviceNames.isNotEmpty, 'Call only when at least one service was removed');

  final isPlural = serviceNames.length > 1;

  final String title = isPlural
      ? 'Services No Longer Available'
      : 'Service No Longer Available';

  final String body;
  if (isPlural) {
    final listed = serviceNames.map((n) => '• $n').join('\n');
    body = "We're sorry, the following services are no longer available "
        'and have been removed from your cart:\n\n$listed';
  } else {
    body = "We're sorry, '${serviceNames.first}' is no longer available "
        'and has been removed from your cart.';
  }

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.remove_shopping_cart_outlined,
                  color: AppColors.error,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
