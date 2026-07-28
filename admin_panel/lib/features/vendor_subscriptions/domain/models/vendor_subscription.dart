class VendorSubscription {
  final String id;
  final String vendorId;
  /// Null for catalog-specific subscriptions.
  final String? planId;
  final String status;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final int renewalCount;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Joined fields
  final String? planName;
  final String? vendorBusinessName;
  final List<SubscriptionPayment> payments;

  /// Non-null when this is a catalog subscription.
  final String? catalogNodeId;
  final String? catalogNodeName;

  const VendorSubscription({
    required this.id,
    required this.vendorId,
    this.planId,
    required this.status,
    this.startDate,
    this.expiryDate,
    required this.renewalCount,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.planName,
    this.vendorBusinessName,
    this.payments = const [],
    this.catalogNodeId,
    this.catalogNodeName,
  });

  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired';
  bool get isCatalogSub => catalogNodeId != null;

  /// Human-readable plan / scope label for display.
  String get displayPlanName {
    if (planName != null) return planName!;
    if (catalogNodeName != null) return 'Catalog: $catalogNodeName';
    return 'Catalog Subscription';
  }

  int get remainingDays {
    if (expiryDate == null) return 0;
    final diff = expiryDate!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory VendorSubscription.fromMap(Map<String, dynamic> map) {
    // PostgREST returns many-to-one joins as a Map and one-to-many as a List.
    // Guard against ambiguous-FK scenarios where the type may differ.
    final plansJoin = map['subscription_plans'];
    final vendorsJoin = map['vendors'];
    final nodesJoin = map['catalog_nodes'];
    final planMap = plansJoin is Map<String, dynamic> ? plansJoin : null;
    final vendorMap = vendorsJoin is Map<String, dynamic> ? vendorsJoin : null;
    final nodeMap = nodesJoin is Map<String, dynamic> ? nodesJoin : null;

    final paymentsRaw = map['vendor_subscription_payments'];
    final paymentsList = paymentsRaw is List ? paymentsRaw : null;

    return VendorSubscription(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      planId: map['plan_id'] as String?,
      status: map['status'] as String? ?? 'pending',
      startDate: _parseDate(map['start_date']),
      expiryDate: _parseDate(map['expiry_date']),
      renewalCount: map['renewal_count'] as int? ?? 0,
      notes: map['notes'] as String?,
      createdAt: _parseDate(map['created_at']),
      updatedAt: _parseDate(map['updated_at']),
      planName: planMap?['name'] as String?,
      vendorBusinessName: vendorMap?['business_name'] as String?,
      catalogNodeId: map['catalog_node_id'] as String?,
      catalogNodeName: nodeMap?['name'] as String?,
      payments: paymentsList == null
          ? []
          : paymentsList
              .map((p) => SubscriptionPayment.fromMap(p as Map<String, dynamic>))
              .toList(),
    );
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  VendorSubscription copyWith({
    String? status,
    DateTime? startDate,
    DateTime? expiryDate,
    int? renewalCount,
    String? notes,
    List<SubscriptionPayment>? payments,
  }) {
    return VendorSubscription(
      id: id,
      vendorId: vendorId,
      planId: planId,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      expiryDate: expiryDate ?? this.expiryDate,
      renewalCount: renewalCount ?? this.renewalCount,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      planName: planName,
      vendorBusinessName: vendorBusinessName,
      payments: payments ?? this.payments,
    );
  }
}

class SubscriptionPayment {
  final String id;
  final String subscriptionId;
  final String vendorId;
  final String paymentType;
  final double amount;
  final String status;
  final String? paymentReference;
  final DateTime? paidAt;
  final String? notes;
  final DateTime? createdAt;

  const SubscriptionPayment({
    required this.id,
    required this.subscriptionId,
    required this.vendorId,
    required this.paymentType,
    required this.amount,
    required this.status,
    this.paymentReference,
    this.paidAt,
    this.notes,
    this.createdAt,
  });

  factory SubscriptionPayment.fromMap(Map<String, dynamic> map) {
    return SubscriptionPayment(
      id: map['id'] as String,
      subscriptionId: map['subscription_id'] as String,
      vendorId: map['vendor_id'] as String,
      paymentType: map['payment_type'] as String? ?? 'subscription_fee',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'pending',
      paymentReference: map['payment_reference'] as String?,
      paidAt: _parseDate(map['paid_at']),
      notes: map['notes'] as String?,
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}

const kSubscriptionStatuses = [
  'pending_payment',
  'pending_approval',
  'pending',
  'active',
  'expired',
  'suspended',
  'cancelled',
];
const kPaymentStatuses = ['pending', 'paid', 'failed', 'refunded'];
const kPaymentTypes = ['joining_fee', 'subscription_fee', 'renewal', 'refund'];
