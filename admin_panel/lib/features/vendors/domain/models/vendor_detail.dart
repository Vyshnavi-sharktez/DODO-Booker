class VendorDocument {
  const VendorDocument({
    required this.id,
    required this.vendorId,
    required this.documentType,
    required this.documentUrl,
    required this.verificationStatus,
    this.customDocumentName,
    this.createdAt,
  });

  final String id;
  final String vendorId;
  final String documentType;
  final String documentUrl;
  final String verificationStatus;
  final String? customDocumentName;
  final DateTime? createdAt;

  static const _typeLabels = {
    'aadhaar_card': 'Aadhaar Card',
    'pan_card': 'PAN Card',
    'gst_certificate': 'GST Certificate',
    'business_license': 'Business License',
    'other': 'Other',
  };

  String get displayName {
    if (documentType == 'other' &&
        (customDocumentName?.isNotEmpty ?? false)) {
      return customDocumentName!;
    }
    return _typeLabels[documentType] ?? documentType;
  }

  factory VendorDocument.fromMap(Map<String, dynamic> m) => VendorDocument(
        id: m['id'] as String,
        vendorId: m['vendor_id'] as String,
        documentType: m['document_type'] as String? ?? '',
        documentUrl: m['document_url'] as String? ?? '',
        verificationStatus:
            m['verification_status'] as String? ?? 'pending',
        customDocumentName: m['custom_document_name'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)
            : null,
      );
}

class VendorServiceArea {
  const VendorServiceArea({
    required this.id,
    required this.city,
    this.area,
    this.pincode,
    this.radiusKm,
  });

  final String id;
  final String city;
  final String? area;
  final String? pincode;
  final double? radiusKm;

  factory VendorServiceArea.fromMap(Map<String, dynamic> m) =>
      VendorServiceArea(
        id: m['id'] as String,
        city: m['city'] as String? ?? '',
        area: m['area'] as String?,
        pincode: m['pincode'] as String?,
        radiusKm: (m['radius_km'] as num?)?.toDouble(),
      );
}

class VendorBookingStats {
  const VendorBookingStats({
    required this.total,
    required this.pending,
    required this.assigned,
    required this.inProgress,
    required this.completed,
    required this.rejected,
    required this.cancelled,
    required this.totalEarnings,
  });

  final int total;
  final int pending;
  final int assigned;
  final int inProgress;
  final int completed;
  final int rejected;
  final int cancelled;
  final double totalEarnings;

  static const empty = VendorBookingStats(
    total: 0,
    pending: 0,
    assigned: 0,
    inProgress: 0,
    completed: 0,
    rejected: 0,
    cancelled: 0,
    totalEarnings: 0,
  );
}
