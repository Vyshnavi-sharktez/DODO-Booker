class ServiceAttributeOption {
  final String id;
  final String attributeId;
  final String optionName;
  final double priceAdjustment;
  final int sortOrder;

  const ServiceAttributeOption({
    required this.id,
    required this.attributeId,
    required this.optionName,
    required this.priceAdjustment,
    this.sortOrder = 0,
  });

  factory ServiceAttributeOption.fromMap(Map<String, dynamic> map) {
    return ServiceAttributeOption(
      id: map['id'] as String,
      attributeId: map['attribute_id'] as String? ?? '',
      optionName: map['option_name'] as String? ?? '',
      priceAdjustment: (map['price_adjustment'] as num?)?.toDouble() ?? 0.0,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  ServiceAttributeOption copyWith({
    String? optionName,
    double? priceAdjustment,
    int? sortOrder,
  }) {
    return ServiceAttributeOption(
      id: id,
      attributeId: attributeId,
      optionName: optionName ?? this.optionName,
      priceAdjustment: priceAdjustment ?? this.priceAdjustment,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
