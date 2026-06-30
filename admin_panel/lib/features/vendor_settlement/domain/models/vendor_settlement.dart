class VendorSettlement {
  final String id;
  final String vendorId;
  final String vendorName;
  final double amount;
  final int completedJobsCount;
  final String? paymentMethod;
  final String? referenceNumber;
  final String? notes;
  final String settledBy;
  final DateTime settledAt;

  const VendorSettlement({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    required this.amount,
    required this.completedJobsCount,
    this.paymentMethod,
    this.referenceNumber,
    this.notes,
    required this.settledBy,
    required this.settledAt,
  });

  factory VendorSettlement.fromMap(Map<String, dynamic> map) {
    return VendorSettlement(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      vendorName: map['vendor_name'] as String? ?? '',
      amount: (map['amount'] as num? ?? 0).toDouble(),
      completedJobsCount: map['completed_jobs_count'] as int? ?? 0,
      paymentMethod: map['payment_method'] as String?,
      referenceNumber: map['reference_number'] as String?,
      notes: map['notes'] as String?,
      settledBy: map['settled_by'] as String? ?? 'Admin',
      settledAt: DateTime.parse(map['settled_at'] as String),
    );
  }
}
