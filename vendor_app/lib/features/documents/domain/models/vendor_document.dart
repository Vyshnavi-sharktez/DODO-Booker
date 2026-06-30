import 'package:flutter/material.dart';

class DocumentTypeModel {
  const DocumentTypeModel({
    required this.id,
    required this.label,
    required this.iconKey,
    this.isRequired = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;
  final String label;
  final String iconKey;
  final bool isRequired;
  final bool isActive;
  final int sortOrder;

  factory DocumentTypeModel.fromJson(Map<String, dynamic> json) {
    return DocumentTypeModel(
      id: json['id'] as String,
      label: json['label'] as String,
      iconKey: (json['icon_key'] as String?) ?? 'description_outlined',
      isRequired: (json['is_required'] as bool?) ?? false,
      isActive: (json['is_active'] as bool?) ?? true,
      sortOrder: (json['sort_order'] as int?) ?? 0,
    );
  }

  IconData get icon => _iconMap[iconKey] ?? Icons.description_outlined;

  static const _iconMap = <String, IconData>{
    'credit_card_outlined':   Icons.credit_card_outlined,
    'perm_identity_outlined': Icons.perm_identity_outlined,
    'receipt_long_outlined':  Icons.receipt_long_outlined,
    'store_outlined':         Icons.store_outlined,
    'description_outlined':   Icons.description_outlined,
    'folder_outlined':        Icons.folder_outlined,
    'badge_outlined':         Icons.badge_outlined,
  };

  // Used when the document_types table is unreachable (table not yet created
  // or network error). Preserves the previous hardcoded enum behaviour.
  static const List<DocumentTypeModel> fallbackList = [
    DocumentTypeModel(id: 'aadhaar_card',     label: 'Aadhaar Card',     iconKey: 'credit_card_outlined',   isRequired: true,  sortOrder: 1),
    DocumentTypeModel(id: 'pan_card',         label: 'PAN Card',         iconKey: 'perm_identity_outlined', isRequired: true,  sortOrder: 2),
    DocumentTypeModel(id: 'gst_certificate',  label: 'GST Certificate',  iconKey: 'receipt_long_outlined',  isRequired: false, sortOrder: 3),
    DocumentTypeModel(id: 'business_license', label: 'Business License', iconKey: 'store_outlined',         isRequired: false, sortOrder: 4),
    DocumentTypeModel(id: 'other',            label: 'Other',            iconKey: 'description_outlined',   isRequired: false, sortOrder: 99),
  ];
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
