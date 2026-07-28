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
  final String? catalogNodeId;
  final String? catalogNodeName;

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
    this.catalogNodeId,
    this.catalogNodeName,
  });

  bool get isCatalogPlan => catalogNodeId != null;
  bool get allowCod => permissions['allow_cod'] == true;
  bool get allowBookingAssignment =>
      permissions['allow_booking_assignment'] == true ||
      permissions['allow_assignment'] == true;
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
    );
  }

  factory SubscriptionPlan.fromCatalogConfig({
    required String nodeId,
    required String nodeName,
    required Map<String, dynamic> config,
  }) {
    final perms = config['permissions'] as Map<String, dynamic>? ?? {};
    return SubscriptionPlan(
      id: 'catalog:$nodeId',
      name: config['name'] as String? ?? nodeName,
      description: config['description'] as String?,
      billingCycle: config['billing_cycle'] as String? ?? 'monthly',
      durationDays: (config['duration_days'] as num?)?.toInt() ?? 30,
      joiningFee: (config['joining_fee'] as num?)?.toDouble(),
      subscriptionFee: (config['subscription_fee'] as num?)?.toDouble(),
      permissions: perms,
      isActive: config['is_active'] as bool? ?? false,
      sortOrder: 0,
      catalogNodeId: nodeId,
      catalogNodeName: nodeName,
    );
  }
}
