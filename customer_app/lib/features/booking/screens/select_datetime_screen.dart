import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/time_slot_model.dart';
import '../services/booking_providers.dart';
import '../widgets/date_selector.dart';
import '../widgets/time_slot_card.dart';

class SelectDatetimeScreen extends ConsumerWidget {
  final DateTime selectedDate;
  final TimeSlotModel? selectedSlot;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeSlotModel> onSlotSelected;

  const SelectDatetimeScreen({
    super.key,
    required this.selectedDate,
    required this.selectedSlot,
    required this.onDateChanged,
    required this.onSlotSelected,
  });

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = _dateKey(selectedDate);
    final slotsAsync = ref.watch(timeSlotsProvider(dateStr));
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date picker header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Select Date',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          DateSelector(
            selectedDate: selectedDate,
            onDateSelected: onDateChanged,
          ),

          const SizedBox(height: 20),

          // Time slots
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Select Time Slot',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),

          slotsAsync.when(
            loading: () => const _SlotsSkeleton(),
            error: (e, _) => const _SlotsError(),
            data: (slots) => _SlotsGrid(
              slots: slots,
              selectedSlot: selectedSlot,
              onSlotSelected: onSlotSelected,
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Slots grid (grouped by period) ────────────────────────────────────────────

class _SlotsGrid extends StatelessWidget {
  final List<TimeSlotModel> slots;
  final TimeSlotModel? selectedSlot;
  final ValueChanged<TimeSlotModel> onSlotSelected;

  const _SlotsGrid({
    required this.slots,
    required this.selectedSlot,
    required this.onSlotSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final grouped = {
      SlotPeriod.morning: slots.where((s) => s.period == SlotPeriod.morning).toList(),
      SlotPeriod.afternoon: slots.where((s) => s.period == SlotPeriod.afternoon).toList(),
      SlotPeriod.evening: slots.where((s) => s.period == SlotPeriod.evening).toList(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final period = entry.key;
        final periodSlots = entry.value;
        if (periodSlots.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_periodIcon(period), size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    period.label,
                    style: tt.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: periodSlots.map((slot) => TimeSlotCard(
                  slot: slot,
                  isSelected: selectedSlot?.id == slot.id,
                  onTap: () => onSlotSelected(slot),
                )).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _periodIcon(SlotPeriod period) {
    switch (period) {
      case SlotPeriod.morning:
        return Icons.wb_sunny_outlined;
      case SlotPeriod.afternoon:
        return Icons.wb_cloudy_outlined;
      case SlotPeriod.evening:
        return Icons.nights_stay_outlined;
    }
  }
}

// ── States ────────────────────────────────────────────────────────────────────

class _SlotsSkeleton extends StatelessWidget {
  const _SlotsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
          12,
          (_) => Container(
            width: 90,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.shimmerBase,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotsError extends StatelessWidget {
  const _SlotsError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Could not load time slots. Please try again.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
