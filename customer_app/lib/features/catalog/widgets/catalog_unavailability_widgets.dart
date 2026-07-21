import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Banner shown in the content area when a catalog node is temporarily
/// unavailable or has been hidden via the admin availability controls.
class CatalogUnavailabilityBanner extends StatelessWidget {
  const CatalogUnavailabilityBanner({
    super.key,
    this.message,
    this.isHidden = false,
  });

  /// Admin-defined customer-facing message (Temporarily Unavailable only).
  final String? message;

  /// True when the node is hidden (no customer message — show generic copy).
  final bool isHidden;

  @override
  Widget build(BuildContext context) {
    if (isHidden) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            children: [
              Icon(Icons.do_not_disturb_rounded,
                  size: 36, color: AppColors.textSecondary),
              SizedBox(height: 12),
              Text(
                'Not Available',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              SizedBox(height: 6),
              Text(
                'This service is not currently available.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFE082)),
        ),
        child: Column(
          children: [
            const Icon(Icons.pause_circle_outline_rounded,
                size: 36, color: Color(0xFFF59E0B)),
            const SizedBox(height: 12),
            const Text(
              'Temporarily Unavailable',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.55),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact bar shown at the bottom of the screen/modal instead of the
/// booking bar when a leaf service is temporarily unavailable or hidden.
class CatalogUnavailabilityBar extends StatelessWidget {
  const CatalogUnavailabilityBar({super.key, this.message});

  /// Admin-defined message; null when node is hidden (show generic text).
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF8E1),
        border: Border(
            top: BorderSide(color: Color(0xFFFFE082), width: 0.8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pause_circle_outline_rounded,
              size: 20, color: Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message?.isNotEmpty == true
                  ? message!
                  : 'This service is not currently available.',
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
