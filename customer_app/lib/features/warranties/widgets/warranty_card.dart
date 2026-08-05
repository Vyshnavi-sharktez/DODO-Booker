import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/my_booking_model.dart';
import '../models/service_warranty_model.dart';
import '../screens/warranty_details_screen.dart';
import '../services/warranty_providers.dart';

class WarrantyCard extends ConsumerWidget {
  final MyBookingModel booking;

  const WarrantyCard({
    super.key,
    required this.booking,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!booking.isCompleted) return const SizedBox.shrink();

    final warrantyAsync = ref.watch(bookingWarrantyProvider(booking.id));

    return warrantyAsync.when(
      data: (warranty) {
        if (warranty == null) return const SizedBox.shrink();
        return _WarrantyCardContent(booking: booking, warranty: warranty);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _WarrantyCardContent extends StatelessWidget {
  final MyBookingModel booking;
  final ServiceWarrantyModel warranty;

  const _WarrantyCardContent({
    required this.booking,
    required this.warranty,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy');

    final statusColor = switch (warranty.effectiveStatus.toLowerCase()) {
      'active' => const Color(0xFF38A169),
      'under review' => const Color(0xFF805AD5),
      'approved' || 'vendor accepted' => const Color(0xFF3182CE),
      'in progress' => const Color(0xFFD69E2E),
      'rework completed' || 'resolved' => const Color(0xFF2B6CB0),
      'rejected' => const Color(0xFFE53E3E),
      _ => const Color(0xFF718096),
    };

    final statusIcon = switch (warranty.effectiveStatus.toLowerCase()) {
      'active' => Icons.verified_user_rounded,
      'under review' => Icons.rate_review_rounded,
      'approved' || 'vendor accepted' => Icons.assignment_turned_in_rounded,
      'in progress' => Icons.engineering_rounded,
      'rework completed' || 'resolved' => Icons.task_alt_rounded,
      'rejected' => Icons.cancel_rounded,
      _ => Icons.history_rounded,
    };

    final statusBg = statusColor.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: Material(
        color: statusBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WarrantyDetailsScreen(
                  booking: booking,
                  warranty: warranty,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(statusIcon, size: 18, color: statusColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Service Warranty',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  warranty.effectiveStatus.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            warranty.isActive
                                ? 'Expires on ${dateFmt.format(warranty.expiresAt)}'
                                : (warranty.isResolved
                                    ? 'Claim resolved'
                                    : (warranty.isClaimed || warranty.isApproved || warranty.isReworkInProgress
                                        ? 'Rework track active'
                                        : (warranty.isRejected
                                            ? 'Claim rejected'
                                            : 'Expired on ${dateFmt.format(warranty.expiresAt)}'))),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (warranty.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${warranty.remainingDays} days left',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondary, size: 20),
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
