import '../../../vendor_tiers/domain/models/vendor_tier.dart';
import '../../../vendors/domain/models/vendor.dart';

class BookingAssignmentRecord {
  final String id;
  final String bookingId;
  final String? bookingNumber;
  final String? vendorId;
  final Vendor? vendor;
  final String? tierId;
  final VendorTier? vendorTier;
  final int? tierPriority;
  final int attemptNumber;
  final String status; // 'pending', 'accepted', 'rejected', 'timed_out'
  final String? rejectionReason;
  final DateTime assignedAt;
  final DateTime? respondedAt;

  const BookingAssignmentRecord({
    required this.id,
    required this.bookingId,
    this.bookingNumber,
    this.vendorId,
    this.vendor,
    this.tierId,
    this.vendorTier,
    this.tierPriority,
    required this.attemptNumber,
    required this.status,
    this.rejectionReason,
    required this.assignedAt,
    this.respondedAt,
  });

  factory BookingAssignmentRecord.fromMap(Map<String, dynamic> map) {
    Vendor? v;
    if (map['vendors'] != null && map['vendors'] is Map<String, dynamic>) {
      v = Vendor.fromMap(map['vendors'] as Map<String, dynamic>);
    }

    VendorTier? vt;
    if (map['vendor_tiers'] != null && map['vendor_tiers'] is Map<String, dynamic>) {
      vt = VendorTier.fromMap(map['vendor_tiers'] as Map<String, dynamic>);
    }

    String? bookingNum;
    if (map['bookings'] != null && map['bookings'] is Map<String, dynamic>) {
      bookingNum = map['bookings']['booking_number'] as String?;
    }

    return BookingAssignmentRecord(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      bookingNumber: bookingNum,
      vendorId: map['vendor_id'] as String?,
      vendor: v,
      tierId: map['tier_id'] as String?,
      vendorTier: vt,
      tierPriority: map['tier_priority'] as int?,
      attemptNumber: map['attempt_number'] as int? ?? 1,
      status: map['status'] as String? ?? 'pending',
      rejectionReason: map['rejection_reason'] as String?,
      assignedAt: DateTime.tryParse(map['assigned_at'] as String? ?? '') ?? DateTime.now(),
      respondedAt: map['responded_at'] != null
          ? DateTime.tryParse(map['responded_at'] as String)
          : null,
    );
  }
}
