import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Shows the "Active AMC Found" dialog when a customer tries to
/// purchase an AMC plan while an active contract already exists.
///
/// Returns:
/// - `'schedule'` → proceed with scheduling the next visit on the existing contract
/// - `'view'`     → navigate to AMC contract details
/// - `null`       → close without action
Future<String?> showActiveAmcDialog(
  BuildContext context, {
  required String serviceName,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final tt = Theme.of(ctx).textTheme;
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.autorenew_rounded,
                color: AppColors.warning,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Active AMC Found'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You already have an active AMC for $serviceName.',
              style: tt.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Schedule your next visit on the existing membership, or view its details.',
              style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
          ],
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Close'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop('view'),
            child: const Text('View AMC'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('schedule'),
            child: const Text('Schedule Next Visit'),
          ),
        ],
      );
    },
  );
}
