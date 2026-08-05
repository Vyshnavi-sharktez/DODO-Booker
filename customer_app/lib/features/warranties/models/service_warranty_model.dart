class ServiceWarrantyModel {
  final String id;
  final String bookingId;
  final String customerId;
  final String? vendorId;
  final int warrantyDays;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String status; // 'Active', 'Expired', 'Claimed', 'Approved', 'Rejected', 'Resolved'
  final DateTime? claimedAt;
  final String? reworkBookingId;
  final String? notes; // Rejection reason or administrative comments
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined / embedded helper fields
  final String? bookingNumber;
  final String? reworkBookingNumber;
  final String? reworkStatus;
  final String? reworkVendorName;
  final DateTime? reworkCompletedAt;
  final DateTime? reworkCreatedAt;
  final String? vendorName;
  final String? issueDescription;

  const ServiceWarrantyModel({
    required this.id,
    required this.bookingId,
    required this.customerId,
    this.vendorId,
    required this.warrantyDays,
    required this.issuedAt,
    required this.expiresAt,
    required this.status,
    this.claimedAt,
    this.reworkBookingId,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.bookingNumber,
    this.reworkBookingNumber,
    this.reworkStatus,
    this.reworkVendorName,
    this.reworkCompletedAt,
    this.reworkCreatedAt,
    this.vendorName,
    this.issueDescription,
  });

  bool get isActive => status.toLowerCase() == 'active' && expiresAt.isAfter(DateTime.now());
  bool get isExpired => status.toLowerCase() == 'expired' || (status.toLowerCase() == 'active' && expiresAt.isBefore(DateTime.now()));
  bool get isClaimed => status.toLowerCase() == 'claimed';
  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';
  bool get isResolved => status.toLowerCase() == 'resolved' || (reworkStatus?.toLowerCase() == 'completed');
  bool get isReworkAccepted => reworkStatus?.toLowerCase() == 'accepted';
  bool get isReworkInProgress => reworkStatus?.toLowerCase() == 'in_progress';
  bool get isReworkCompleted => reworkStatus?.toLowerCase() == 'completed' || reworkStatus?.toLowerCase() == 'awaiting_verification';

  bool get canClaim => isActive && !isClaimed && !isApproved && !isResolved && reworkBookingId == null;

  String get effectiveStatus {
    if (isResolved) return 'Resolved';
    if (isReworkCompleted) return 'Rework Completed';
    if (isReworkInProgress) return 'In Progress';
    if (isReworkAccepted) return 'Vendor Accepted';
    if (isApproved) return 'Approved';
    if (isRejected) return 'Rejected';
    if (isClaimed) return 'Under Review';
    if (isExpired) return 'Expired';
    return 'Active';
  }

  int get remainingDays {
    if (isExpired || isClaimed || isApproved || isRejected || isResolved) return 0;
    final diff = expiresAt.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  String get certificateNumber {
    final year = issuedAt.year;
    final code = id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
    return 'WRT-$year-$code';
  }

  static String cleanIssueDescription(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'No detailed description provided.';
    var text = raw.trim();

    final regex = RegExp(r'\[WARRANTY REWORK\]\s*(Claim for Booking\s*#?[a-zA-Z0-9\-]+:?\s*)?', caseSensitive: false);
    text = text.replaceAll(regex, '').trim();

    final claimRegex = RegExp(r'^Claim for Booking\s*#?[a-zA-Z0-9\-]+:?\s*', caseSensitive: false);
    text = text.replaceAll(claimRegex, '').trim();

    if (text.isEmpty) return 'No detailed description provided.';
    return text;
  }

  factory ServiceWarrantyModel.fromJson(Map<String, dynamic> json) {
    String? bNum;
    if (json['bookings'] != null && json['bookings'] is Map<String, dynamic>) {
      bNum = json['bookings']['booking_number'] as String?;
    }

    String? rNum;
    String? rStatus;
    String? rVendorName;
    DateTime? rCompletedAt;
    DateTime? rCreatedAt;
    String? rawIssueDesc;
    String? vId = json['vendor_id'] as String?;

    if (json['rework_booking'] != null && json['rework_booking'] is Map<String, dynamic>) {
      final rb = json['rework_booking'] as Map<String, dynamic>;
      rNum = rb['booking_number'] as String?;
      rStatus = rb['status'] as String?;
      rawIssueDesc = rb['notes'] as String?;
      vId ??= rb['vendor_id'] as String?;
      if (rb['completed_at'] != null) {
        rCompletedAt = DateTime.tryParse(rb['completed_at'] as String);
      }
      if (rb['created_at'] != null) {
        rCreatedAt = DateTime.tryParse(rb['created_at'] as String);
      }
      if (rb['vendors'] != null && rb['vendors'] is Map<String, dynamic>) {
        rVendorName = rb['vendors']['business_name'] as String?;
      }
    }

    rawIssueDesc ??= json['notes'] as String?;
    final cleanedIssue = cleanIssueDescription(rawIssueDesc);

    String? vName;
    if (json['vendors'] != null && json['vendors'] is Map<String, dynamic>) {
      vName = json['vendors']['business_name'] as String?;
    }
    vName ??= rVendorName;
    rVendorName ??= vName;

    final issued = DateTime.tryParse(json['issued_at'] as String? ?? '') ?? DateTime.now();
    final expires = DateTime.tryParse(json['expires_at'] as String? ?? '') ?? issued.add(const Duration(days: 30));

    return ServiceWarrantyModel(
      id: json['id'] as String,
      bookingId: json['booking_id'] as String,
      customerId: json['customer_id'] as String,
      vendorId: vId,
      warrantyDays: json['warranty_days'] as int? ?? 30,
      issuedAt: issued,
      expiresAt: expires,
      status: json['status'] as String? ?? 'Active',
      claimedAt: json['claimed_at'] != null ? DateTime.tryParse(json['claimed_at'] as String) : null,
      reworkBookingId: json['rework_booking_id'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      bookingNumber: bNum,
      reworkBookingNumber: rNum,
      reworkStatus: rStatus,
      reworkVendorName: rVendorName,
      reworkCompletedAt: rCompletedAt,
      reworkCreatedAt: rCreatedAt,
      vendorName: vName,
      issueDescription: cleanedIssue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'booking_id': bookingId,
      'customer_id': customerId,
      'vendor_id': vendorId,
      'warranty_days': warrantyDays,
      'issued_at': issuedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'status': status,
      'claimed_at': claimedAt?.toIso8601String(),
      'rework_booking_id': reworkBookingId,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
