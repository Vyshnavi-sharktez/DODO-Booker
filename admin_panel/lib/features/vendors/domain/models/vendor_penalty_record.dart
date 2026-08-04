class VendorPenaltyRecord {
  const VendorPenaltyRecord({
    required this.id,
    required this.vendorId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.balanceBefore,
    this.referenceId,
    this.referenceType,
    this.description,
    this.createdBy,
    required this.createdAt,
    this.bookingNumber,
    this.serviceName,
  });

  final String id;
  final String vendorId;
  final String type; // 'penalty'
  final double amount;
  final double balanceAfter;
  final double balanceBefore;
  final String? referenceId; // booking UUID or null
  final String? referenceType; // 'booking', 'manual', etc.
  final String? description; // reason
  final String? createdBy; // admin UUID or null
  final DateTime createdAt;
  final String? bookingNumber;
  final String? serviceName;

  bool get isManual => referenceType == 'manual' || createdBy != null;

  String get appliedBy => isManual ? 'Admin' : 'System (Automatic)';

  String get penaltyTypeLabel => isManual ? 'Manual Penalty' : 'Automatic Penalty';

  factory VendorPenaltyRecord.fromMap(Map<String, dynamic> map) {
    final amount = (map['amount'] as num).toDouble();
    final balanceAfter = (map['balance_after'] as num).toDouble();
    final balanceBefore = balanceAfter + amount;

    String? bookingNum;
    String? srvName;

    if (map['bookings'] != null && map['bookings'] is Map<String, dynamic>) {
      final bMap = map['bookings'] as Map<String, dynamic>;
      bookingNum = bMap['booking_number'] as String?;
      if (bMap['booking_items'] != null && (bMap['booking_items'] as List).isNotEmpty) {
        final item = (bMap['booking_items'] as List).first as Map<String, dynamic>;
        if (item['catalog_nodes'] != null && item['catalog_nodes'] is Map<String, dynamic>) {
          srvName = (item['catalog_nodes'] as Map<String, dynamic>)['name'] as String?;
        }
      }
    }

    return VendorPenaltyRecord(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      type: map['type'] as String? ?? 'penalty',
      amount: amount,
      balanceAfter: balanceAfter,
      balanceBefore: balanceBefore,
      referenceId: map['reference_id'] as String?,
      referenceType: map['reference_type'] as String?,
      description: map['description'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      bookingNumber: bookingNum,
      serviceName: srvName,
    );
  }
}
