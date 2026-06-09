class Coupon {
  final String id;
  final String code;
  final String? description;
  final String discountType;
  final double discountValue;
  final double? minOrderAmount;
  final double? minDiscountAmount;
  final int? usageLimit;
  final int usedCount;
  final DateTime? validFrom;
  final DateTime? validTo;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Coupon({
    required this.id,
    required this.code,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.minOrderAmount,
    this.minDiscountAmount,
    this.usageLimit,
    this.usedCount = 0,
    this.validFrom,
    this.validTo,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  bool get isExpired {
    if (validTo == null) return false;
    return validTo!.isBefore(DateTime.now());
  }

  bool get isUsageLimitReached {
    if (usageLimit == null) return false;
    return usedCount >= usageLimit!;
  }

  factory Coupon.fromMap(Map<String, dynamic> map) {
    return Coupon(
      id: map['id'] as String,
      code: map['code'] as String? ?? '',
      description: map['description'] as String?,
      discountType: map['discount_type'] as String? ?? 'percentage',
      discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0.0,
      minOrderAmount: (map['min_order_amount'] as num?)?.toDouble(),
      minDiscountAmount: (map['min_discount_amount'] as num?)?.toDouble(),
      usageLimit: map['usage_limit'] as int?,
      usedCount: map['used_count'] as int? ?? 0,
      validFrom: map['valid_from'] != null
          ? DateTime.tryParse(map['valid_from'] as String)
          : null,
      validTo: map['valid_to'] != null
          ? DateTime.tryParse(map['valid_to'] as String)
          : null,
      isActive: map['is_active'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Coupon copyWith({
    String? code,
    String? description,
    String? discountType,
    double? discountValue,
    double? minOrderAmount,
    double? minDiscountAmount,
    int? usageLimit,
    int? usedCount,
    DateTime? validFrom,
    DateTime? validTo,
    bool? isActive,
  }) {
    return Coupon(
      id: id,
      code: code ?? this.code,
      description: description ?? this.description,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      minOrderAmount: minOrderAmount ?? this.minOrderAmount,
      minDiscountAmount: minDiscountAmount ?? this.minDiscountAmount,
      usageLimit: usageLimit ?? this.usageLimit,
      usedCount: usedCount ?? this.usedCount,
      validFrom: validFrom ?? this.validFrom,
      validTo: validTo ?? this.validTo,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
