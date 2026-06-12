enum SlotPeriod { morning, afternoon, evening }

extension SlotPeriodLabel on SlotPeriod {
  String get label {
    switch (this) {
      case SlotPeriod.morning:
        return 'Morning';
      case SlotPeriod.afternoon:
        return 'Afternoon';
      case SlotPeriod.evening:
        return 'Evening';
    }
  }
}

class TimeSlotModel {
  final String id;
  final String label;
  final SlotPeriod period;
  final bool isAvailable;

  const TimeSlotModel({
    required this.id,
    required this.label,
    required this.period,
    this.isAvailable = true,
  });

  factory TimeSlotModel.fromJson(Map<String, dynamic> json) {
    return TimeSlotModel(
      id: json['id'] as String,
      label: json['label'] as String,
      period: SlotPeriod.values.firstWhere(
        (p) => p.name == (json['period'] as String),
        orElse: () => SlotPeriod.morning,
      ),
      isAvailable: (json['is_available'] as bool?) ?? true,
    );
  }
}
