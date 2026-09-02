class ServiceAttributeOption {
  final String id;
  final String attributeId;
  final String optionName;
  final double priceAdjustment;
  final int sortOrder;
  final String discountType;
  final double discountValue;

  const ServiceAttributeOption({
    required this.id,
    required this.attributeId,
    required this.optionName,
    required this.priceAdjustment,
    this.sortOrder = 0,
    this.discountType = 'percentage',
    this.discountValue = 0,
  });

  double get discountAmount => discountType == 'percentage'
      ? priceAdjustment * discountValue / 100
      : discountValue;

  double get finalPrice =>
      (priceAdjustment - discountAmount).clamp(0.0, double.infinity);

  bool get hasDiscount => discountValue > 0;

  factory ServiceAttributeOption.fromMap(Map<String, dynamic> map) {
    return ServiceAttributeOption(
      id: map['id'] as String,
      attributeId: map['attribute_id'] as String? ?? '',
      optionName: map['option_name'] as String? ?? '',
      priceAdjustment: (map['price_adjustment'] as num?)?.toDouble() ?? 0.0,
      sortOrder: map['sort_order'] as int? ?? 0,
      discountType: (map['discount_type'] as String?) ?? 'percentage',
      discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0,
    );
  }

  ServiceAttributeOption copyWith({
    String? optionName,
    double? priceAdjustment,
    int? sortOrder,
    String? discountType,
    double? discountValue,
  }) {
    return ServiceAttributeOption(
      id: id,
      attributeId: attributeId,
      optionName: optionName ?? this.optionName,
      priceAdjustment: priceAdjustment ?? this.priceAdjustment,
      sortOrder: sortOrder ?? this.sortOrder,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
    );
  }
}
