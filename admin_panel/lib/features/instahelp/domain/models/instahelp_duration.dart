class InstaHelpDuration {
  final String id;
  final String modeId;
  final String label;
  final int durationMinutes;
  final double price;
  final String discountType; // 'none' | 'percentage' | 'fixed'
  final double discountValue;
  final bool isActive;
  final int sortOrder;
  final String slotStartTime;
  final String slotEndTime;
  final int slotIntervalMinutes;
  final int maxBookingsPerSlot;
  final DateTime? createdAt;

  const InstaHelpDuration({
    required this.id,
    required this.modeId,
    required this.label,
    required this.durationMinutes,
    required this.price,
    required this.discountType,
    required this.discountValue,
    required this.isActive,
    required this.sortOrder,
    required this.slotStartTime,
    required this.slotEndTime,
    required this.slotIntervalMinutes,
    required this.maxBookingsPerSlot,
    this.createdAt,
  });

  double get discountAmount {
    if (discountType == 'percentage') return price * discountValue / 100;
    if (discountType == 'fixed') return discountValue;
    return 0;
  }

  double get finalPrice => (price - discountAmount).clamp(0.0, double.infinity);

  bool get hasDiscount => discountType != 'none' && discountValue > 0;

  factory InstaHelpDuration.fromMap(Map<String, dynamic> map) =>
      InstaHelpDuration(
        id: map['id'] as String,
        modeId: map['mode_id'] as String,
        label: map['label'] as String,
        durationMinutes: (map['duration_minutes'] as num).toInt(),
        price: (map['price'] as num).toDouble(),
        discountType: map['discount_type'] as String? ?? 'none',
        discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0,
        isActive: map['is_active'] as bool? ?? true,
        sortOrder: map['sort_order'] as int? ?? 0,
        slotStartTime: map['slot_start_time'] as String? ?? '08:00',
        slotEndTime: map['slot_end_time'] as String? ?? '20:00',
        slotIntervalMinutes: (map['slot_interval_minutes'] as num?)?.toInt() ?? 60,
        maxBookingsPerSlot: (map['max_bookings_per_slot'] as num?)?.toInt() ?? 10,
        createdAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String)
            : null,
      );

  InstaHelpDuration copyWith({
    String? label,
    int? durationMinutes,
    double? price,
    String? discountType,
    double? discountValue,
    bool? isActive,
    int? sortOrder,
    String? slotStartTime,
    String? slotEndTime,
    int? slotIntervalMinutes,
    int? maxBookingsPerSlot,
  }) =>
      InstaHelpDuration(
        id: id,
        modeId: modeId,
        label: label ?? this.label,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        price: price ?? this.price,
        discountType: discountType ?? this.discountType,
        discountValue: discountValue ?? this.discountValue,
        isActive: isActive ?? this.isActive,
        sortOrder: sortOrder ?? this.sortOrder,
        slotStartTime: slotStartTime ?? this.slotStartTime,
        slotEndTime: slotEndTime ?? this.slotEndTime,
        slotIntervalMinutes: slotIntervalMinutes ?? this.slotIntervalMinutes,
        maxBookingsPerSlot: maxBookingsPerSlot ?? this.maxBookingsPerSlot,
        createdAt: createdAt,
      );
}
