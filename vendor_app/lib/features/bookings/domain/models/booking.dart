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

  bool get isDodoTeam => assignmentType == 'DODO Team';

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
    );
  }

  Booking copyWith({String? status, String? notes}) {
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
    );
  }
}
