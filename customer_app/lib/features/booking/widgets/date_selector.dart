import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

class DateSelector extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final int daysAhead;

  const DateSelector({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.daysAhead = 14,
  });

  @override
  State<DateSelector> createState() => _DateSelectorState();
}

class _DateSelectorState extends State<DateSelector> {
  final ScrollController _scroll = ScrollController();

  static const _dayAbbrevs = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _monthAbbrevs = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<DateTime> get _dates {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    return List.generate(widget.daysAhead, (i) => base.add(Duration(days: i)));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayLabel(DateTime date) {
    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);
    if (_isSameDay(date, todayNorm)) return 'Today';
    if (_isSameDay(date, todayNorm.add(const Duration(days: 1)))) return 'Tomorrow';
    return _dayAbbrevs[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;

    return SizedBox(
      height: 80,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final date = dates[i];
          final selected = _isSameDay(date, widget.selectedDate);
          return _DateCard(
            date: date,
            dayLabel: _dayLabel(date),
            monthLabel: _monthAbbrevs[date.month - 1],
            isSelected: selected,
            onTap: () => widget.onDateSelected(date),
          );
        },
      ),
    );
  }
}

class _DateCard extends StatelessWidget {
  final DateTime date;
  final String dayLabel;
  final String monthLabel;
  final bool isSelected;
  final VoidCallback onTap;

  const _DateCard({
    required this.date,
    required this.dayLabel,
    required this.monthLabel,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 62,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            Text(
              monthLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white70 : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
