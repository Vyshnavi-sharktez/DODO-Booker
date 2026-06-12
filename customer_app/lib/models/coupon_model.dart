class CouponModel {
  final String id;
  final String code;
  final String? description;
  final String discountType; // 'percentage' | 'flat'
  final double discountValue;
  final double? minOrderAmount;
  final double? maxDiscountAmount;
  final int? usageLimit;
  final int usedCount;
  final DateTime? validFrom;
  final DateTime? validTo;
  final bool isActive;

  const CouponModel({
    required this.id,
    required this.code,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.minOrderAmount,
    this.maxDiscountAmount,
    this.usageLimit,
    this.usedCount = 0,
    this.validFrom,
    this.validTo,
    required this.isActive,
  });

  factory CouponModel.fromMap(Map<String, dynamic> map) {
    return CouponModel(
      id: map['id'] as String,
      code: map['code'] as String? ?? '',
      description: map['description'] as String?,
      discountType: map['discount_type'] as String? ?? 'percentage',
      discountValue: (map['discount_value'] as num?)?.toDouble() ?? 0.0,
      minOrderAmount: (map['min_order_amount'] as num?)?.toDouble(),
      maxDiscountAmount: (map['max_discount_amount'] as num?)?.toDouble(),
      usageLimit: map['usage_limit'] as int?,
      usedCount: map['used_count'] as int? ?? 0,
      validFrom: map['valid_from'] != null
          ? DateTime.tryParse(map['valid_from'] as String)
          : null,
      validTo: map['valid_to'] != null
          ? DateTime.tryParse(map['valid_to'] as String)
          : null,
      isActive: map['is_active'] as bool? ?? false,
    );
  }

  // Returns an error string if invalid, null if valid.
  String? validate(double subtotal) {
    if (!isActive) return 'This coupon is not active.';
    final now = DateTime.now();
    if (validFrom != null && now.isBefore(validFrom!)) {
      return 'This coupon is not valid yet.';
    }
    if (validTo != null && now.isAfter(validTo!)) {
      return 'This coupon has expired.';
    }
    if (usageLimit != null && usedCount >= usageLimit!) {
      return 'This coupon has reached its usage limit.';
    }
    if (minOrderAmount != null && subtotal < minOrderAmount!) {
      return 'Minimum order amount is ₹${minOrderAmount!.toStringAsFixed(0)}.';
    }
    return null;
  }

  double calculateDiscount(double subtotal) {
    if (discountType == 'percentage') {
      final discount = subtotal * (discountValue / 100);
      if (maxDiscountAmount != null) {
        return discount.clamp(0.0, maxDiscountAmount!);
      }
      return discount.clamp(0.0, subtotal);
    }
    // flat
    return discountValue.clamp(0.0, subtotal);
  }

  String get discountLabel {
    if (discountType == 'percentage') {
      final pct = discountValue.toStringAsFixed(
          discountValue == discountValue.floorToDouble() ? 0 : 1);
      final cap = maxDiscountAmount != null
          ? ' (up to ₹${maxDiscountAmount!.toStringAsFixed(0)})'
          : '';
      return '$pct% off$cap';
    }
    return '₹${discountValue.toStringAsFixed(0)} off';
  }

  String get expiryLabel {
    if (validTo == null) return 'No expiry';
    final d = validTo!;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Expires ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
