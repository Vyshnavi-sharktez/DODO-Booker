import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_modal_dialog.dart';
import '../../../models/time_slot_model.dart';
import '../services/booking_providers.dart';
import '../widgets/date_selector.dart';
import '../widgets/time_slot_card.dart';

/// Date & time slot selection modal.
/// Pops with a `(DateTime, TimeSlotModel)` record when the user confirms, or null.
class DateTimeModal extends ConsumerStatefulWidget {
  const DateTimeModal({super.key});

  @override
  ConsumerState<DateTimeModal> createState() => _DateTimeModalState();
}

class _DateTimeModalState extends ConsumerState<DateTimeModal> {
  DateTime _date = DateTime.now();
  TimeSlotModel? _slot;

  String get _dateKey =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final slotsAsync = ref.watch(timeSlotsProvider(_dateKey));

    return AppModalDialog(
      title: 'Select Date & Time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),

          // Date picker
          Text(
            'Select Date',
            style: tt.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          DateSelector(
            selectedDate: _date,
            onDateSelected: (d) => setState(() {
              _date = d;
              _slot = null;
            }),
          ),

          const SizedBox(height: 20),

          // Time slots
          Text(
            'Select Time Slot',
            style: tt.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          slotsAsync.when(
            loading: () => const _SlotSkeleton(),
            error: (e, st) => const _SlotError(),
            data: (slots) => _SlotsGrid(
              slots: slots,
              selected: _slot,
              onSelect: (s) => setState(() => _slot = s),
            ),
          ),

          const SizedBox(height: 20),
          FilledButton(
            onPressed: _slot != null
                ? () => Navigator.of(context).pop((_date, _slot!))
                : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text(
              'Confirm Date & Time',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotsGrid extends StatelessWidget {
  final List<TimeSlotModel> slots;
  final TimeSlotModel? selected;
  final ValueChanged<TimeSlotModel> onSelect;

  const _SlotsGrid({
    required this.slots,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final grouped = {
      SlotPeriod.morning:
          slots.where((s) => s.period == SlotPeriod.morning).toList(),
      SlotPeriod.afternoon:
          slots.where((s) => s.period == SlotPeriod.afternoon).toList(),
      SlotPeriod.evening:
          slots.where((s) => s.period == SlotPeriod.evening).toList(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final period = entry.key;
        final periodSlots = entry.value;
        if (periodSlots.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_periodIcon(period), size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    period.label,
                    style: tt.labelSmall?.copyWith(
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
                children: periodSlots
                    .map((slot) => TimeSlotCard(
                          slot: slot,
                          isSelected: selected?.id == slot.id,
                          onTap: slot.isAvailable ? () => onSelect(slot) : null,
                        ))
                    .toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _periodIcon(SlotPeriod p) => switch (p) {
        SlotPeriod.morning => Icons.wb_sunny_outlined,
        SlotPeriod.afternoon => Icons.wb_cloudy_outlined,
        SlotPeriod.evening => Icons.nights_stay_outlined,
      };
}

class _SlotSkeleton extends StatelessWidget {
  const _SlotSkeleton();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(
        12,
        (_) => Container(
          width: 88,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.shimmerBase,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _SlotError extends StatelessWidget {
  const _SlotError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'Could not load time slots.',
        textAlign: TextAlign.center,
      ),
    );
  }
}
