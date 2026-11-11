class InstaHelpSlotModel {
  final String slotTime;
  final bool isAvailable;
  final int bookingsCount;
  final int maxBookings;

  const InstaHelpSlotModel({
    required this.slotTime,
    required this.isAvailable,
    required this.bookingsCount,
    required this.maxBookings,
  });

  factory InstaHelpSlotModel.fromMap(Map<String, dynamic> m) {
    return InstaHelpSlotModel(
      slotTime: m['slot_time'] as String,
      isAvailable: m['is_available'] as bool,
      bookingsCount: m['bookings_count'] as int,
      maxBookings: m['max_bookings'] as int,
    );
  }
}

class InstaHelpInstantAvailability {
  final bool isAvailable;
  final int? opensInMinutes;

  const InstaHelpInstantAvailability({
    required this.isAvailable,
    this.opensInMinutes,
  });

  factory InstaHelpInstantAvailability.fromMap(Map<String, dynamic> m) {
    return InstaHelpInstantAvailability(
      isAvailable: m['is_available'] as bool,
      opensInMinutes: m['opens_in_minutes'] as int?,
    );
  }
}
