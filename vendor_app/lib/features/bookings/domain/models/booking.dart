import 'booking_item.dart';

class Booking {
  const Booking({
    required this.id,
    required this.bookingNumber,
    required this.customerId,
    required this.status,
    this.assignmentType = 'External Vendor',
    required this.subtotal,
    required this.totalAmount,
    this.serviceDate,
    this.address,
    this.notes,
    this.serviceName,
    this.customerName,
    this.customerPhone,
    this.discountAmount = 0.0,
    this.createdAt,
    this.rejectionReason,
    this.rejectedAt,
    this.completionOtp,
    this.otpVerifiedAt,
    this.items = const [],
    this.isAmc = false,
    this.amcPlanName,
    this.amcRecurrenceInterval,
    this.amcContractId,
    this.paymentMethod = 'cash',
    this.codCashCollected,
    this.codNotCollectedReason,
    this.codConfirmedAt,
    this.dispatchStatus,
    this.lastDispatchAttemptAt,
    this.tierTimeoutSeconds = 60,
  });

  final String id;
  final String bookingNumber;
  final String customerId;
  final String status;
  // 'External Vendor' | 'DODO Team' | 'Unassigned'
  final String assignmentType;
  final double subtotal;
  final double totalAmount;
  final DateTime? serviceDate;
  final String? address;
  final String? notes;
  final String? serviceName;
  final String? customerName;
  final String? customerPhone;
  final double discountAmount;
  final DateTime? createdAt;
  final String? rejectionReason;
  final DateTime? rejectedAt;
  final String? completionOtp;
  final DateTime? otpVerifiedAt;
  final List<BookingItem> items;
  final bool isAmc;
  final String? amcPlanName;
  final String? amcRecurrenceInterval;
  final String? amcContractId;
  final String paymentMethod;
  final bool? codCashCollected;
  final String? codNotCollectedReason;
  final DateTime? codConfirmedAt;

  // Dispatch fields
  final String? dispatchStatus;
  final DateTime? lastDispatchAttemptAt;
  final int tierTimeoutSeconds;

  bool get isDodoTeam => assignmentType == 'DODO Team';

  bool get isCod =>
      paymentMethod.toLowerCase() == 'cash' || paymentMethod.toLowerCase() == 'cod';

  bool get isCodCollectionPending =>
      isCod && status == 'completed' && codConfirmedAt == null;

  bool get isWarrantyRework => (notes ?? '').contains('[WARRANTY REWORK]');

  String? get originalBookingNumber {
    if (!isWarrantyRework) return null;
    final match = RegExp(r'Booking #([A-Za-z0-9\-]+)').firstMatch(notes ?? '');
    return match?.group(1);
  }

  String? get reworkIssueDescription {
    if (!isWarrantyRework) return null;
    final index = (notes ?? '').indexOf('Issue: ');
    if (index != -1) {
      return (notes ?? '').substring(index + 7).trim();
    }
    return notes;
  }

  factory Booking.fromMap(Map<String, dynamic> map) {
    final rawItems = map['booking_items'] as List<dynamic>? ?? [];
    final items = rawItems
        .map((e) => BookingItem.fromMap(e as Map<String, dynamic>))
        .toList();

    return Booking(
      id: map['id'] as String,
      bookingNumber: map['booking_number'] as String? ?? '',
      customerId: map['customer_id'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      assignmentType: map['assignment_type'] as String? ?? 'External Vendor',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0.0,
      serviceDate: map['service_date'] != null
          ? DateTime.tryParse(map['service_date'] as String)
          : null,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      rejectionReason: map['rejection_reason'] as String?,
      rejectedAt: map['rejected_at'] != null
          ? DateTime.tryParse(map['rejected_at'] as String)
          : null,
      completionOtp: map['completion_otp'] as String?,
      otpVerifiedAt: map['otp_verified_at'] != null
          ? DateTime.tryParse(map['otp_verified_at'] as String)
          : null,
      items: items,
      isAmc: map['is_amc'] as bool? ?? false,
      amcPlanName: map['amc_plan_name'] as String?,
      amcRecurrenceInterval: map['amc_recurrence_interval'] as String?,
      amcContractId: map['amc_contract_id'] as String?,
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      codCashCollected: map['cod_cash_collected'] as bool?,
      codNotCollectedReason: map['cod_not_collected_reason'] as String?,
      codConfirmedAt: map['cod_confirmed_at'] != null
          ? DateTime.tryParse(map['cod_confirmed_at'] as String)
          : null,
      dispatchStatus: map['dispatch_status'] as String?,
      lastDispatchAttemptAt: map['last_dispatch_attempt_at'] != null
          ? DateTime.tryParse(map['last_dispatch_attempt_at'] as String)
          : null,
      tierTimeoutSeconds: map['tier_timeout_seconds'] as int? ?? 60,
    );
  }

  Booking copyWith({
    String? status,
    String? notes,
    String? dispatchStatus,
    DateTime? lastDispatchAttemptAt,
    int? tierTimeoutSeconds,
    bool? codCashCollected,
    String? codNotCollectedReason,
    DateTime? codConfirmedAt,
  }) {
    return Booking(
      id: id,
      bookingNumber: bookingNumber,
      customerId: customerId,
      status: status ?? this.status,
      assignmentType: assignmentType,
      subtotal: subtotal,
      totalAmount: totalAmount,
      discountAmount: discountAmount,
      serviceDate: serviceDate,
      address: address,
      notes: notes ?? this.notes,
      serviceName: serviceName,
      customerName: customerName,
      customerPhone: customerPhone,
      createdAt: createdAt,
      rejectionReason: rejectionReason,
      rejectedAt: rejectedAt,
      completionOtp: completionOtp,
      otpVerifiedAt: otpVerifiedAt,
      items: items,
      isAmc: isAmc,
      amcPlanName: amcPlanName,
      amcRecurrenceInterval: amcRecurrenceInterval,
      amcContractId: amcContractId,
      paymentMethod: paymentMethod,
      codCashCollected: codCashCollected ?? this.codCashCollected,
      codNotCollectedReason: codNotCollectedReason ?? this.codNotCollectedReason,
      codConfirmedAt: codConfirmedAt ?? this.codConfirmedAt,
      dispatchStatus: dispatchStatus ?? this.dispatchStatus,
      lastDispatchAttemptAt:
          lastDispatchAttemptAt ?? this.lastDispatchAttemptAt,
      tierTimeoutSeconds: tierTimeoutSeconds ?? this.tierTimeoutSeconds,
    );
  }
}
