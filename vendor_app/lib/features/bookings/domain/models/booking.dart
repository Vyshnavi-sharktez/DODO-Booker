class Booking {
  const Booking({
    required this.id,
    required this.bookingNumber,
    required this.customerId,
    required this.status,
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
  });

  final String id;
  final String bookingNumber;
  final String customerId;
  final String status;
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

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id'] as String,
      bookingNumber: map['booking_number'] as String? ?? '',
      customerId: map['customer_id'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
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
    );
  }

  Booking copyWith({String? status, String? notes}) {
    return Booking(
      id: id,
      bookingNumber: bookingNumber,
      customerId: customerId,
      status: status ?? this.status,
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
    );
  }
}
