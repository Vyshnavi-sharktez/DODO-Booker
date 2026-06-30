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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    : Colors.transparent,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          slot.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : available
                    ? AppColors.textPrimary
                    : AppColors.textHint,
            decoration: available ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}
