class ServiceAddon {
  final String id;
  final String name;
  final String? description;
  final double price;
  final bool isActive;
  final String? serviceId;
  final DateTime? createdAt;
  final String discountType;
  final double discountValue;

  const ServiceAddon({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    required this.isActive,
    this.serviceId,
    this.createdAt,
    this.discountType = 'percentage',
    this.discountValue = 0,
  });

  double get discountAmount => discountType == 'percentage'
      ? price * discountValue / 100
      : discountValue;

  double get finalPrice =>
      (price - discountAmount).clamp(0.0, double.infinity);

  bool get hasDiscount => discountValue > 0;

  factory ServiceAddon.fromMap(Map<String, dynamic> map) {
    return ServiceAddon(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      isActive: map['is_active'] as bool? ?? true,
      serviceId: map['service_id'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      discountType: (map['discount_type'] as String?) ?? 'percentage',
      discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0,
    );
  }

  ServiceAddon copyWith({
    String? name,
    String? description,
    double? price,
    bool? isActive,
    Object? serviceId = _sentinel,
    String? discountType,
    double? discountValue,
  }) {
    return ServiceAddon(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
      serviceId: serviceId == _sentinel
          ? this.serviceId
          : serviceId as String?,
      createdAt: createdAt,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
    );
  }
}

// Sentinel for copyWith optional nullable field.
const _sentinel = Object();
