import 'subscription_plan.dart';

class VendorSubscription {
  final String id;
  final String vendorId;
  final String? planId;
  final String? catalogNodeId;
  final String? catalogNodeName;
  final String status;
  final DateTime? startDate;
  final DateTime? expiryDate;
  final int renewalCount;
  final String? notes;
  final DateTime? createdAt;
  final SubscriptionPlan? plan;
  final List<SubscriptionPayment> payments;

  const VendorSubscription({
    required this.id,
    required this.vendorId,
    this.planId,
    this.catalogNodeId,
    this.catalogNodeName,
    required this.status,
    this.startDate,
    this.expiryDate,
    required this.renewalCount,
    this.notes,
    this.createdAt,
    this.plan,
    this.payments = const [],
  });

  bool get isCatalogSub => catalogNodeId != null;
  String get displayPlanName =>
      plan?.name ?? (catalogNodeName != null ? 'Catalog: $catalogNodeName' : 'Subscription');
  bool get isActive => status == 'active';

  SubscriptionPayment? get pendingPayment =>
      payments.where((p) => p.status == 'pending').firstOrNull;

  int get remainingDays {
    if (expiryDate == null) return 0;
    final diff = expiryDate!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  bool get isExpiringSoon => isActive && remainingDays <= 7;

  factory VendorSubscription.fromMap(Map<String, dynamic> map) {
    final planRaw = map['subscription_plans'];
    final nodeRaw = map['catalog_nodes'];
    final paymentsRaw = map['vendor_subscription_payments'];
    final planMap = planRaw is Map<String, dynamic> ? planRaw : null;
    final nodeMap = nodeRaw is Map<String, dynamic> ? nodeRaw : null;
    final paymentsList = paymentsRaw is List ? paymentsRaw : null;

    return VendorSubscription(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      planId: map['plan_id'] as String?,
      catalogNodeId: map['catalog_node_id'] as String?,
      catalogNodeName: nodeMap?['name'] as String?,
      status: map['status'] as String? ?? 'pending',
      startDate: _parseDate(map['start_date']),
      expiryDate: _parseDate(map['expiry_date']),
      renewalCount: map['renewal_count'] as int? ?? 0,
      notes: map['notes'] as String?,
      createdAt: _parseDate(map['created_at']),
      plan: planMap != null ? SubscriptionPlan.fromMap(planMap) : null,
      payments: paymentsList == null
          ? []
          : paymentsList
              .map((p) => SubscriptionPayment.fromMap(p as Map<String, dynamic>))
              .toList(),
    );
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}

class SubscriptionPayment {
  final String id;
  final String paymentType;
  final double amount;
  final String status;
  final String? paymentReference;
  final DateTime? paidAt;
  final DateTime? createdAt;

  const SubscriptionPayment({
    required this.id,
    required this.paymentType,
    required this.amount,
    required this.status,
    this.paymentReference,
    this.paidAt,
    this.createdAt,
  });

  factory SubscriptionPayment.fromMap(Map<String, dynamic> map) {
    return SubscriptionPayment(
      id: map['id'] as String,
      paymentType: map['payment_type'] as String? ?? 'subscription_fee',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'pending',
      paymentReference: map['payment_reference'] as String?,
      paidAt: _parseDate(map['paid_at']),
      createdAt: _parseDate(map['created_at']),
    );
  }

  static DateTime? _parseDate(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString());
}
