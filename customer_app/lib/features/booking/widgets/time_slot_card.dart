import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/clickable.dart';
import '../../../models/time_slot_model.dart';

class TimeSlotCard extends StatelessWidget {
  final TimeSlotModel slot;
  final bool isSelected;
  final VoidCallback? onTap;

  const TimeSlotCard({
    super.key,
    required this.slot,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final available = slot.isAvailable;

    return Clickable(
      onTap: available ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : available
                  ? AppColors.surface
                  : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : available
                    ? AppColors.border
                    : AppColors.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: available
            ? Text(
                slot.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    slot.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textHint,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sold Out',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
