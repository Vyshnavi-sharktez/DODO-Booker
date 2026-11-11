class InstaHelpSlotConfig {
  final String id;
  final String modeId;
  final List<int> workingDays;
  final String startTime;
  final String endTime;
  final int slotIntervalMinutes;
  final int maxBookingsPerSlot;
  final bool isActive;

  const InstaHelpSlotConfig({
    required this.id,
    required this.modeId,
    required this.workingDays,
    required this.startTime,
    required this.endTime,
    required this.slotIntervalMinutes,
    required this.maxBookingsPerSlot,
    required this.isActive,
  });

  factory InstaHelpSlotConfig.fromMap(Map<String, dynamic> m) => InstaHelpSlotConfig(
        id: m['id'] as String,
        modeId: m['mode_id'] as String,
        workingDays: (m['working_days'] as List).map((e) => e as int).toList(),
        startTime: m['start_time'] as String,
        endTime: m['end_time'] as String,
        slotIntervalMinutes: m['slot_interval_minutes'] as int,
        maxBookingsPerSlot: m['max_bookings_per_slot'] as int,
        isActive: m['is_active'] as bool,
      );

  static const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
}
