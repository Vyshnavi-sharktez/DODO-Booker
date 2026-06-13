class RejectedBookingRecord {
  const RejectedBookingRecord({
    required this.id,
    required this.bookingNumber,
    required this.totalAmount,
    required this.rejectedAt,
    required this.rejectionReason,
    this.notes,
    this.serviceDate,
    this.address,
  });

  final String id;
  final String bookingNumber;
  final double totalAmount;
  final DateTime rejectedAt;
  final String rejectionReason;
  final String? notes;
  final DateTime? serviceDate;
  final String? address;

  Map<String, dynamic> toJson() => {
        'id': id,
        'booking_number': bookingNumber,
        'total_amount': totalAmount,
        'rejected_at': rejectedAt.toIso8601String(),
        'rejection_reason': rejectionReason,
        if (notes != null) 'notes': notes,
        if (serviceDate != null) 'service_date': serviceDate!.toIso8601String(),
        if (address != null) 'address': address,
      };

  factory RejectedBookingRecord.fromJson(Map<String, dynamic> json) {
    return RejectedBookingRecord(
      id: json['id'] as String,
      bookingNumber: json['booking_number'] as String,
      totalAmount: (json['total_amount'] as num).toDouble(),
      rejectedAt: DateTime.parse(json['rejected_at'] as String),
      rejectionReason: (json['rejection_reason'] as String?) ?? '',
      notes: json['notes'] as String?,
      serviceDate: json['service_date'] != null
          ? DateTime.tryParse(json['service_date'] as String)
          : null,
      address: json['address'] as String?,
    );
  }
}
