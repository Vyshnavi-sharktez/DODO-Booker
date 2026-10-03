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
  final String serviceId;
  final String? parentNodeId;
  const DateTimeModal({super.key, required this.serviceId, this.parentNodeId});

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
    final slotsAsync = ref.watch(timeSlotsProvider(
      (date: _dateKey, serviceId: widget.serviceId, parentNodeId: widget.parentNodeId, vendorId: null),
    ));

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
    if (slots.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
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
            isSelected: selected?.id == slots[i].id,
            onTap: slots[i].isAvailable ? () => onSelect(slots[i]) : null,
          ),
        );
      },
    );
  }
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
