import 'package:flutter/material.dart';

enum DocumentType {
  aadhaar('aadhaar_card', 'Aadhaar Card', Icons.credit_card_outlined),
  pan('pan_card', 'PAN Card', Icons.perm_identity_outlined),
  gst('gst_certificate', 'GST Certificate', Icons.receipt_long_outlined),
  businessLicense('business_license', 'Business License', Icons.store_outlined),
  other('other', 'Other', Icons.description_outlined);

  const DocumentType(this.value, this.label, this.icon);
  final String value;
  final String label;
  final IconData icon;

  static DocumentType? fromValue(String value) =>
      DocumentType.values.where((d) => d.value == value).firstOrNull;
}

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

  factory VendorDocument.fromMap(Map<String, dynamic> map) {
    return VendorDocument(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      documentType: map['document_type'] as String? ?? '',
      documentUrl: map['document_url'] as String? ?? '',
      verificationStatus: map['verification_status'] as String? ?? 'pending',
      customDocumentName: map['custom_document_name'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }
}
