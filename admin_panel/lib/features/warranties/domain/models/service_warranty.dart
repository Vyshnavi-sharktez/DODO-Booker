class ServiceWarranty {
  final String id;
  final String bookingId;
  final String customerId;
  final String? vendorId;
  final int warrantyDays;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String status; // 'Active', 'Expired', 'Claimed', 'Approved', 'Rejected'
  final DateTime? claimedAt;
  final String? reworkBookingId;
  final String? notes; // Rejection reason or administrative comments
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined/embedded helper fields
  final String? bookingNumber;
  final String? reworkBookingNumber;
  final String? reworkStatus;
  final String? reworkVendorName;
  final DateTime? reworkCompletedAt;
  final DateTime? reworkCreatedAt;
  final String? vendorName;
  final String? customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String? issueDescription;

  const ServiceWarranty({
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
    this.customerName,
    this.customerEmail,
    this.customerPhone,
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

  String get effectiveStatus {
    if (isResolved) return 'Resolved';
    if (isReworkInProgress) return 'In Progress';
    if (isReworkAccepted) return 'Vendor Accepted';
    if (isApproved) return 'Approved';
    if (isRejected) return 'Rejected';
    if (isClaimed) return 'Claimed';
    if (isExpired) return 'Expired';
    return status;
  }

  String get certificateNumber {
    final year = issuedAt.year;
    final code = id.replaceAll('-', '').substring(0, 6).toUpperCase();
    return 'WRT-$year-$code';
  }

  int get remainingDays {
    if (isExpired || isClaimed || isApproved || isRejected) return 0;
    final diff = expiresAt.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  static String cleanIssueDescription(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'No detailed description provided.';
    var text = raw.trim();

    // Strip internal prefix: "[WARRANTY REWORK] Claim for Booking #<uuid/number>: "
    final regex = RegExp(r'\[WARRANTY REWORK\]\s*(Claim for Booking\s*#?[a-zA-Z0-9\-]+:?\s*)?', caseSensitive: false);
    text = text.replaceAll(regex, '').trim();

    // Strip leftover prefix: "Claim for Booking #<uuid/number>: "
    final claimRegex = RegExp(r'^Claim for Booking\s*#?[a-zA-Z0-9\-]+:?\s*', caseSensitive: false);
    text = text.replaceAll(claimRegex, '').trim();

    if (text.isEmpty) return 'No detailed description provided.';
    return text;
  }

  ServiceWarranty copyWith({
    String? id,
    String? bookingId,
    String? customerId,
    String? vendorId,
    int? warrantyDays,
    DateTime? issuedAt,
    DateTime? expiresAt,
    String? status,
    DateTime? claimedAt,
    String? reworkBookingId,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? bookingNumber,
    String? reworkBookingNumber,
    String? reworkStatus,
    String? reworkVendorName,
    DateTime? reworkCompletedAt,
    DateTime? reworkCreatedAt,
    String? vendorName,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? issueDescription,
  }) {
    return ServiceWarranty(
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      customerId: customerId ?? this.customerId,
      vendorId: vendorId ?? this.vendorId,
      warrantyDays: warrantyDays ?? this.warrantyDays,
      issuedAt: issuedAt ?? this.issuedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      status: status ?? this.status,
      claimedAt: claimedAt ?? this.claimedAt,
      reworkBookingId: reworkBookingId ?? this.reworkBookingId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      bookingNumber: bookingNumber ?? this.bookingNumber,
      reworkBookingNumber: reworkBookingNumber ?? this.reworkBookingNumber,
      reworkStatus: reworkStatus ?? this.reworkStatus,
      reworkVendorName: reworkVendorName ?? this.reworkVendorName,
      reworkCompletedAt: reworkCompletedAt ?? this.reworkCompletedAt,
      reworkCreatedAt: reworkCreatedAt ?? this.reworkCreatedAt,
      vendorName: vendorName ?? this.vendorName,
      customerName: customerName ?? this.customerName,
      customerEmail: customerEmail ?? this.customerEmail,
      customerPhone: customerPhone ?? this.customerPhone,
      issueDescription: issueDescription ?? this.issueDescription,
    );
  }

  factory ServiceWarranty.fromMap(Map<String, dynamic> map) {
    String? bNum;
    if (map['bookings'] != null && map['bookings'] is Map<String, dynamic>) {
      bNum = map['bookings']['booking_number'] as String?;
    }

    String? rNum;
    String? rStatus;
    String? rVendorName;
    DateTime? rCompletedAt;
    DateTime? rCreatedAt;
    String? rawIssueDesc;
    String? vId = map['vendor_id'] as String?;

    if (map['rework_booking'] != null && map['rework_booking'] is Map<String, dynamic>) {
      final rb = map['rework_booking'] as Map<String, dynamic>;
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

    rawIssueDesc ??= map['notes'] as String?;
    final cleanedIssue = cleanIssueDescription(rawIssueDesc);

    String? vName;
    if (map['vendors'] != null && map['vendors'] is Map<String, dynamic>) {
      vName = map['vendors']['business_name'] as String?;
    }
    vName ??= rVendorName;
    rVendorName ??= vName;

    String? cName;
    String? cEmail;
    String? cPhone;

    void extractCustomer(dynamic custData) {
      if (custData != null && custData is Map<String, dynamic>) {
        cName ??= custData['full_name'] as String? ?? custData['name'] as String?;
        cEmail ??= custData['email'] as String?;
        cPhone ??= custData['phone'] as String?;
      }
    }

    extractCustomer(map['customers']);
    extractCustomer(map['profiles']);

    if (map['bookings'] != null && map['bookings'] is Map<String, dynamic>) {
      final b = map['bookings'] as Map<String, dynamic>;
      bNum ??= b['booking_number'] as String?;
      extractCustomer(b['customers']);
      extractCustomer(b['profiles']);
    }

    if (map['rework_booking'] != null && map['rework_booking'] is Map<String, dynamic>) {
      final rb = map['rework_booking'] as Map<String, dynamic>;
      extractCustomer(rb['customers']);
      extractCustomer(rb['profiles']);
    }

    final issued = DateTime.tryParse(map['issued_at'] as String? ?? '') ?? DateTime.now();
    final expires = DateTime.tryParse(map['expires_at'] as String? ?? '') ?? issued.add(const Duration(days: 30));

    return ServiceWarranty(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      customerId: map['customer_id'] as String,
      vendorId: vId,
      warrantyDays: map['warranty_days'] as int? ?? 30,
      issuedAt: issued,
      expiresAt: expires,
      status: map['status'] as String? ?? 'Active',
      claimedAt: map['claimed_at'] != null ? DateTime.tryParse(map['claimed_at'] as String) : null,
      reworkBookingId: map['rework_booking_id'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
      bookingNumber: bNum,
      reworkBookingNumber: rNum,
      reworkStatus: rStatus,
      reworkVendorName: rVendorName,
      reworkCompletedAt: rCompletedAt,
      reworkCreatedAt: rCreatedAt,
      vendorName: vName,
      customerName: cName,
      customerEmail: cEmail,
      customerPhone: cPhone,
      issueDescription: cleanedIssue,
    );
  }

  Map<String, dynamic> toMap() {
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
