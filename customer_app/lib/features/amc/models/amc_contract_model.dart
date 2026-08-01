class AmcVisitModel {
  final String id;
  final int? visitNumber;
  final String status;
  final DateTime? serviceDate;
  final String timeSlot;
  final double totalAmount;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? vendorName;

  const AmcVisitModel({
    required this.id,
    this.visitNumber,
    required this.status,
    this.serviceDate,
    required this.timeSlot,
    required this.totalAmount,
    required this.createdAt,
    this.completedAt,
    this.vendorName,
  });

  factory AmcVisitModel.fromMap(
    Map<String, dynamic> m, {
    String? vendorName,
  }) =>
      AmcVisitModel(
        id: m['id'] as String,
        visitNumber: (m['amc_visit_number'] as num?)?.toInt(),
        status: m['status'] as String? ?? 'pending',
        serviceDate: m['service_date'] != null
            ? DateTime.tryParse(m['service_date'] as String)
            : null,
        timeSlot: m['scheduled_time'] as String? ?? '',
        totalAmount: (m['total_amount'] as num?)?.toDouble() ?? 0.0,
        createdAt: DateTime.parse(m['created_at'] as String),
        completedAt: m['otp_verified_at'] != null
            ? DateTime.tryParse(m['otp_verified_at'] as String)
            : null,
        vendorName: vendorName,
      );
}

class AmcContractModel {
  final String id;
  final String serviceId;
  final String serviceName;
  final String planName;
  final String recurrenceInterval;
  final double pricePerVisit;
  final String status; // 'active' | 'paused' | 'completed' | 'cancelled' | 'cancellation_requested'
  final int totalVisits; // legacy column
  final DateTime createdAt;

  // Snapshot fields added in 20260729_amc_plans.sql
  final String? amcPlanId;
  final String? packageDuration;
  final String? serviceInterval;
  final int? numVisits;
  final double? originalTotal;
  final String? discountType;
  final double? discountValue;
  final double? discountAmount;
  final double? finalPrice;

  final String? cancellationReason;
  final String? cancellationRemarks;
  final DateTime? cancellationRequestedAt;

  // Renewal / quantity fields added in 20260801000001_amc_quantity_renewal.sql
  final int quantity;
  final String? previousContractId;
  final bool isRenewal;

  final List<AmcVisitModel> visits;

  bool get isCancellationRequested => status == 'cancellation_requested';
  bool get isRenewable => status == 'completed' || (status == 'active' && remainingVisits == 0);

  const AmcContractModel({
    required this.id,
    required this.serviceId,
    required this.serviceName,
    required this.planName,
    required this.recurrenceInterval,
    required this.pricePerVisit,
    required this.status,
    required this.totalVisits,
    required this.createdAt,
    this.amcPlanId,
    this.packageDuration,
    this.serviceInterval,
    this.numVisits,
    this.originalTotal,
    this.discountType,
    this.discountValue,
    this.discountAmount,
    this.finalPrice,
    this.cancellationReason,
    this.cancellationRemarks,
    this.cancellationRequestedAt,
    this.quantity = 1,
    this.previousContractId,
    this.isRenewal = false,
    this.visits = const [],
  });

  int get effectiveTotalVisits => numVisits ?? totalVisits;

  int get completedVisits =>
      visits.where((v) => v.status == 'completed').length;

  int get remainingVisits =>
      (effectiveTotalVisits - completedVisits).clamp(0, 9999);

  factory AmcContractModel.fromMap(
    Map<String, dynamic> m, {
    List<AmcVisitModel> visits = const [],
  }) =>
      AmcContractModel(
        id: m['id'] as String,
        serviceId: m['service_id'] as String? ?? '',
        serviceName: m['service_name'] as String? ?? '',
        planName: m['plan_name'] as String? ?? '',
        recurrenceInterval: m['recurrence_interval'] as String? ?? '',
        pricePerVisit: (m['price_per_visit'] as num?)?.toDouble() ?? 0.0,
        status: m['status'] as String? ?? 'active',
        totalVisits: (m['total_visits'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String),
        amcPlanId: m['amc_plan_id'] as String?,
        packageDuration: m['package_duration'] as String?,
        serviceInterval: m['service_interval'] as String?,
        numVisits: (m['num_visits'] as num?)?.toInt(),
        originalTotal: (m['original_total'] as num?)?.toDouble(),
        discountType: m['discount_type'] as String?,
        discountValue: (m['discount_value'] as num?)?.toDouble(),
        discountAmount: (m['discount_amount'] as num?)?.toDouble(),
        finalPrice: (m['final_price'] as num?)?.toDouble(),
        cancellationReason: m['cancellation_reason'] as String?,
        cancellationRemarks: m['cancellation_remarks'] as String?,
        cancellationRequestedAt: m['cancellation_requested_at'] != null
            ? DateTime.tryParse(m['cancellation_requested_at'] as String)
            : null,
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        previousContractId: m['previous_contract_id'] as String?,
        isRenewal: m['is_renewal'] as bool? ?? false,
        visits: visits,
      );
}
