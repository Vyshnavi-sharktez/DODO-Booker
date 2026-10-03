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
        // No padding — the grid cell provides the size; alignment centres text.
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary          // dark near-black fill
              : available
                  ? AppColors.surface      // white
                  : AppColors.surfaceVariant, // muted warm-grey
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.border,        // same subtle border for both states
            width: 1,
          ),
        ),
        child: Text(
          slot.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : available
                    ? AppColors.textPrimary
                    : AppColors.textHint,  // dimmed; no strikethrough
          ),
        ),
      ),
    );
  }
}
