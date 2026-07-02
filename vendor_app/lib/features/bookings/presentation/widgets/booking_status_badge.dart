import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class BookingStatusBadge extends StatelessWidget {
  const BookingStatusBadge({super.key, required this.status});

  final String status;

  Color get _color => switch (status) {
        'pending' => AppColors.statusPending,
        'assigned' => AppColors.statusAssigned,
        'assigned_to_dodo_team' => AppColors.primary,
        'in_progress' => AppColors.statusInProgress,
        'awaiting_verification' => AppColors.warning,
        'completed' => AppColors.statusCompleted,
        'cancelled' => AppColors.statusCancelled,
        'rejected' => AppColors.error,
        _ => AppColors.textHint,
      };

  String get _label => switch (status) {
        'pending' => 'Pending',
        'assigned' => 'Assigned',
        'assigned_to_dodo_team' => 'DODO Assigned',
        'in_progress' => 'In Progress',
        'awaiting_verification' => 'Awaiting OTP',
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        'rejected' => 'Rejected',
        _ => status.replaceAll('_', ' '),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: _color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
