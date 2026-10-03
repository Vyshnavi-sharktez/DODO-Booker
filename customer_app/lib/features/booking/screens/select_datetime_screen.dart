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
  final String serviceId;

  const SelectDatetimeScreen({
    super.key,
    required this.selectedDate,
    required this.selectedSlot,
    required this.onDateChanged,
    required this.onSlotSelected,
    required this.serviceId,
  });

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateStr = _dateKey(selectedDate);
    final slotsAsync = ref.watch(timeSlotsProvider((date: dateStr, serviceId: serviceId, parentNodeId: null, vendorId: null)));
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
            data: (slots) {
              if (slots.isEmpty) {
                return _NoSlotsState(
                  onSelectTomorrow: () {
                    onDateChanged(
                      selectedDate.add(const Duration(days: 1)),
                    );
                  },
                );
              }
              return _SlotsGrid(
                slots: slots,
                selectedSlot: selectedSlot,
                onSlotSelected: onSlotSelected,
              );
            },
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
    if (slots.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth >= 460 ? 4 : constraints.maxWidth >= 300 ? 3 : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: (constraints.maxWidth - (cols - 1) * 8) / cols / 44,
            ),
            itemCount: slots.length,
            itemBuilder: (_, i) => TimeSlotCard(
              slot: slots[i],
              isSelected: selectedSlot?.id == slots[i].id,
              onTap: slots[i].isAvailable ? () => onSlotSelected(slots[i]) : null,
            ),
          );
        },
      ),
    );
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

class _NoSlotsState extends StatelessWidget {
  final VoidCallback onSelectTomorrow;

  const _NoSlotsState({required this.onSelectTomorrow});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 52,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              'No slots available today',
              style: tt.titleSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'All time slots have passed.\nPlease select another date.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onSelectTomorrow,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text("View Tomorrow's Slots"),
            ),
          ],
        ),
      ),
    );
  }
}
