import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Shows a compact, centered "service not available" dialog.
/// Uses the dialog builder context for Navigator.pop so it works correctly
/// inside GoRouter-nested navigators.
///
/// [message] overrides the default body text. Use it to show a service-specific
/// reason (e.g. "Deep Cleaning is not available in your area."). When null the
/// generic platform-wide copy is shown instead.
Future<void> showServiceAreaUnavailableDialog(
  BuildContext context, {
  String? message,
}) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
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
                    color: AppColors.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_off_rounded,
                    color: AppColors.textSecondary,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Service Not Available in Your Area',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message ??
                      "We're sorry, DODO Booker is not currently serving your "
                      "area. We're expanding quickly and hope to serve you soon.",
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
