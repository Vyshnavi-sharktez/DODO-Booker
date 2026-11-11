class InstaHelpDurationModel {
  final String id;
  final String modeId;
  final String label;
  final int durationMinutes;
  final double price;
  final String discountType;
  final double discountValue;
  final int sortOrder;

  const InstaHelpDurationModel({
    required this.id,
    required this.modeId,
    required this.label,
    required this.durationMinutes,
    required this.price,
    required this.discountType,
    required this.discountValue,
    required this.sortOrder,
  });

  double get discountAmount {
    if (discountType == 'percentage') return price * discountValue / 100;
    if (discountType == 'fixed') return discountValue;
    return 0;
  }

  double get finalPrice => (price - discountAmount).clamp(0.0, double.infinity);

  bool get hasDiscount => discountType != 'none' && discountValue > 0;

  factory InstaHelpDurationModel.fromMap(Map<String, dynamic> map) =>
      InstaHelpDurationModel(
        id: map['id'] as String,
        modeId: map['mode_id'] as String,
        label: map['label'] as String,
        durationMinutes: (map['duration_minutes'] as num).toInt(),
        price: (map['price'] as num).toDouble(),
        discountType: map['discount_type'] as String? ?? 'none',
        discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0,
        sortOrder: map['sort_order'] as int? ?? 0,
      );
}
