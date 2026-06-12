import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class BookingStatusBadge extends StatelessWidget {
  const BookingStatusBadge({super.key, required this.status});

  final String status;

  Color get _color => switch (status) {
        'pending' => AppColors.statusPending,
        'assigned' => AppColors.statusAssigned,
        'in_progress' => AppColors.statusInProgress,
        'completed' => AppColors.statusCompleted,
        'cancelled' => AppColors.statusCancelled,
        _ => AppColors.textHint,
      };

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
