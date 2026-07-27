class SubscriptionPlan {
  final String id;
  final String name;
  final String? description;
  final String billingCycle;
  final int durationDays;
  final double? joiningFee;
  final double? subscriptionFee;
  final Map<String, dynamic> permissions;
  final bool isActive;
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    this.description,
    required this.billingCycle,
    required this.durationDays,
    this.joiningFee,
    this.subscriptionFee,
    required this.permissions,
    required this.isActive,
    required this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  bool get allowCod => permissions['allow_cod'] == true;
  bool get allowBookingAssignment => permissions['allow_booking_assignment'] == true;
  bool get priorityListing => permissions['priority_listing'] == true;
  double get reducedCommissionPct =>
      (permissions['reduced_commission_pct'] as num?)?.toDouble() ?? 0.0;

  factory SubscriptionPlan.fromMap(Map<String, dynamic> map) {
    return SubscriptionPlan(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String?,
      billingCycle: map['billing_cycle'] as String? ?? 'monthly',
      durationDays: map['duration_days'] as int? ?? 30,
      joiningFee: (map['joining_fee'] as num?)?.toDouble(),
      subscriptionFee: (map['subscription_fee'] as num?)?.toDouble(),
      permissions: (map['permissions'] as Map<String, dynamic>?) ?? {},
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: map['sort_order'] as int? ?? 0,
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  SubscriptionPlan copyWith({
    String? name,
    String? description,
    String? billingCycle,
    int? durationDays,
    double? joiningFee,
    double? subscriptionFee,
    Map<String, dynamic>? permissions,
    bool? isActive,
    int? sortOrder,
  }) {
    return SubscriptionPlan(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      billingCycle: billingCycle ?? this.billingCycle,
      durationDays: durationDays ?? this.durationDays,
      joiningFee: joiningFee ?? this.joiningFee,
      subscriptionFee: subscriptionFee ?? this.subscriptionFee,
      permissions: permissions ?? this.permissions,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

const kBillingCycles = ['daily', 'weekly', 'monthly', 'quarterly', 'yearly', 'custom'];
