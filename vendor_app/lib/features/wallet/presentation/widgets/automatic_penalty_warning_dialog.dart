import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/wallet_provider.dart';

/// Shows a warning dialog before an action that triggers an automatic penalty.
/// If the rule is disabled or amount == 0, returns normal confirmation without warning text.
Future<bool> showAutomaticPenaltyWarningDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String eventType,
  required String actionTitle,
  required String reasonLabel,
}) async {
  try {
    final rule = await ref
        .read(walletRepositoryProvider)
        .fetchPenaltyRule(eventType);

    if (!context.mounted) return false;

    if (!rule.isEnabled || rule.amount <= 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(actionTitle),
          content: Text('Are you sure you want to proceed with $actionTitle?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      return confirmed ?? false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 22),
            SizedBox(width: 8),
            Text('Penalty Warning'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proceeding with $actionTitle will incur an automatic penalty of ₹${rule.amount.toStringAsFixed(2)} which will be deducted from your wallet balance.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Reason: $reasonLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Booking'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text('Proceed & Pay ₹${rule.amount.toStringAsFixed(2)}'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  } catch (_) {
    return true;
  }
}
