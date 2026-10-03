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

  // Applicability
  final String applicabilityType;         // 'all' | 'categories' | 'services'
  final List<String> applicableNodeIds;   // catalog_node IDs
  final List<String> applicableNodeNames; // resolved names for display

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
    this.applicabilityType = 'all',
    this.applicableNodeIds = const [],
    this.applicableNodeNames = const [],
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
      applicabilityType: map['applicability_type'] as String? ?? 'all',
      applicableNodeIds: (map['applicable_node_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      applicableNodeNames: (map['applicable_node_names'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  CouponModel copyWith({
    List<String>? applicableNodeNames,
  }) {
    return CouponModel(
      id: id,
      code: code,
      description: description,
      discountType: discountType,
      discountValue: discountValue,
      minOrderAmount: minOrderAmount,
      maxDiscountAmount: maxDiscountAmount,
      usageLimit: usageLimit,
      usedCount: usedCount,
      validFrom: validFrom,
      validTo: validTo,
      isActive: isActive,
      applicabilityType: applicabilityType,
      applicableNodeIds: applicableNodeIds,
      applicableNodeNames: applicableNodeNames ?? this.applicableNodeNames,
    );
  }

  // Returns an error string if the coupon is not valid, null if valid.
  // cartNodeIds: union of serviceId + parentNodeId + rootCategoryId for all
  // cart items — used for client-side applicability pre-check.
  String? validate(double subtotal, {List<String> cartNodeIds = const []}) {
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
    // Applicability — client-side pre-check (server is authoritative at submit)
    if (applicabilityType != 'all' &&
        applicableNodeIds.isNotEmpty &&
        cartNodeIds.isNotEmpty) {
      final applicable = cartNodeIds.any((id) => applicableNodeIds.contains(id));
      if (!applicable) {
        return applicabilityErrorMessage;
      }
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

  // Human-readable applicability label for display in coupon cards/banners.
  // e.g. "10% OFF on Cleaning Services"  or  "Valid on all services"
  String get applicabilityLabel {
    if (applicabilityType == 'all' || applicableNodeNames.isEmpty) {
      return 'Valid on all services';
    }
    if (applicableNodeNames.length == 1) {
      return 'Valid on ${applicableNodeNames.first}';
    }
    if (applicableNodeNames.length <= 3) {
      return 'Valid on ${applicableNodeNames.join(', ')}';
    }
    final first = applicableNodeNames.take(2).join(', ');
    return 'Valid on $first & ${applicableNodeNames.length - 2} more';
  }

  // Context-aware label shown on coupon cards when the cart is known.
  // Avoids listing service names; instead signals cart match/mismatch.
  String contextualApplicabilityLabel(List<String> cartNodeIds) {
    if (applicabilityType == 'all' || applicableNodeIds.isEmpty) {
      return 'Valid on all services';
    }
    if (cartNodeIds.isEmpty) return 'Restricted to specific services';
    final ok = cartNodeIds.any((id) => applicableNodeIds.contains(id));
    return ok ? 'Applicable to this service' : 'Not applicable for this service';
  }

  // True when the cart passes the applicability check.
  // Returns true when there's no cart context (browse mode).
  bool isCartApplicable(List<String> cartNodeIds) {
    if (applicabilityType == 'all' || applicableNodeIds.isEmpty ||
        cartNodeIds.isEmpty) {
      return true;
    }
    return cartNodeIds.any((id) => applicableNodeIds.contains(id));
  }

  // Error message used when the coupon doesn't match the cart.
  String get applicabilityErrorMessage {
    if (applicableNodeNames.isEmpty) {
      return 'This coupon is not valid for items in your cart.';
    }
    if (applicableNodeNames.length == 1) {
      return 'This coupon is valid only on ${applicableNodeNames.first}.';
    }
    return 'This coupon is valid only on: ${applicableNodeNames.join(', ')}.';
  }
}
