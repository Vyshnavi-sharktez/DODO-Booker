import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class BookingStepper extends StatelessWidget {
  final int currentStep;

  const BookingStepper({super.key, required this.currentStep});

  static const _steps = [
    (Icons.location_on_rounded, 'Address'),
    (Icons.calendar_today_rounded, 'Date & Time'),
    (Icons.receipt_long_rounded, 'Summary'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            child: Container(
              height: 2,
              color: i ~/ 2 < currentStep ? AppColors.primary : AppColors.border,
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final isCompleted = stepIndex < currentStep;
        final isCurrent = stepIndex == currentStep;
        return _StepDot(
          icon: _steps[stepIndex].$1,
          label: _steps[stepIndex].$2,
          isCompleted: isCompleted,
          isCurrent: isCurrent,
        );
      }),
    );
  }
}

class _StepDot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isCompleted;
  final bool isCurrent;

  const _StepDot({
    required this.icon,
    required this.label,
    required this.isCompleted,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color borderColor;

    if (isCompleted) {
      bg = AppColors.primary;
      fg = Colors.white;
      borderColor = AppColors.primary;
    } else if (isCurrent) {
      bg = AppColors.primaryLight;
      fg = AppColors.primary;
      borderColor = AppColors.primary;
    } else {
      bg = Colors.transparent;
      fg = AppColors.textHint;
      borderColor = AppColors.border;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Icon(
            isCompleted ? Icons.check_rounded : icon,
            size: 18,
            color: fg,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
            color: isCurrent ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
