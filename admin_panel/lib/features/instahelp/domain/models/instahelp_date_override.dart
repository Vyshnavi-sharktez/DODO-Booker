class InstaHelpDateOverride {
  final String id;
  final String modeId;
  final DateTime startDate;
  final DateTime endDate;
  final bool isAvailable;
  final String? customStartTime;
  final String? customEndTime;
  final String? notes;

  const InstaHelpDateOverride({
    required this.id,
    required this.modeId,
    required this.startDate,
    required this.endDate,
    required this.isAvailable,
    this.customStartTime,
    this.customEndTime,
    this.notes,
  });

  bool get isSingleDay =>
      startDate.year == endDate.year &&
      startDate.month == endDate.month &&
      startDate.day == endDate.day;

  factory InstaHelpDateOverride.fromMap(Map<String, dynamic> m) {
    return InstaHelpDateOverride(
      id: m['id'] as String,
      modeId: m['mode_id'] as String,
      startDate: DateTime.parse(m['start_date'] as String),
      endDate: DateTime.parse(m['end_date'] as String),
      isAvailable: m['is_available'] as bool,
      customStartTime: m['custom_start_time'] as String?,
      customEndTime: m['custom_end_time'] as String?,
      notes: m['notes'] as String?,
    );
  }
}
