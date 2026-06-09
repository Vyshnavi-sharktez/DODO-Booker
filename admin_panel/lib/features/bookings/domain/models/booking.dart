class Booking {
  final String id;
  final String bookingNumber;
  final String customerId;
  final String vendorId;
  final DateTime? serviceDate;
  final String status;
  final double subtotal;
  final double discountAmount;
  final double totalAmount;
  final String? address;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Booking({
    required this.id,
    required this.bookingNumber,
    required this.customerId,
    required this.vendorId,
    this.serviceDate,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.totalAmount,
    this.address,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory Booking.fromMap(Map<String, dynamic> map) {
    return Booking(
      id: map['id'] as String,
      bookingNumber: map['booking_number'] as String? ?? '',
      customerId: map['customer_id'] as String? ?? '',
      vendorId: map['vendor_id'] as String? ?? '',
      serviceDate: map['service_date'] != null
          ? DateTime.tryParse(map['service_date'] as String)
          : null,
      status: map['status'] as String? ?? 'pending',
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Booking copyWith({
    String? vendorId,
    DateTime? serviceDate,
    String? status,
    String? notes,
  }) {
    return Booking(
      id: id,
      bookingNumber: bookingNumber,
      customerId: customerId,
      vendorId: vendorId ?? this.vendorId,
      serviceDate: serviceDate ?? this.serviceDate,
      status: status ?? this.status,
      subtotal: subtotal,
      discountAmount: discountAmount,
      totalAmount: totalAmount,
      address: address,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
