import 'package:intl/intl.dart';

class VendorServiceRequest {
  const VendorServiceRequest({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    this.vendorTier,
    required this.serviceName,
    this.description,
    this.price,
    this.activePrice,
    this.newPrice,
    this.imageUrl,
    required this.status,
    this.rejectionReason,
    required this.requestType,
    this.parentRequestId,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = false,
    this.warrantyEnabled = false,
    this.warrantyDays,
    this.warrantyCovers,
    this.warrantyExclusions,
    this.includedItems = const [],
    this.excludedItems = const [],
    this.beforeAfterPairs = const [],
  });

  final String id;
  final String vendorId;
  final String vendorName;
  final String? vendorTier;
  final String serviceName;
  final String? description;
  final double? price;
  final double? activePrice;
  final double? newPrice;
  final String? imageUrl;
  final String status; // pending | needs_catalog | completed | rejected | deleted | pending_deletion
  final String? rejectionReason;
  final String requestType; // new_service | price_change | delete_service
  final String? parentRequestId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final bool warrantyEnabled;
  final int? warrantyDays;
  final String? warrantyCovers;
  final String? warrantyExclusions;
  final List<String> includedItems;
  final List<String> excludedItems;
  final List<Map<String, String>> beforeAfterPairs;

  bool get isPending => status == 'pending';
  bool get isNeedsCatalog => status == 'needs_catalog';
  bool get isCompleted => status == 'completed';
  bool get isRejected => status == 'rejected';
  bool get isDeleted => status == 'deleted';
  bool get isPendingDeletion => status == 'pending_deletion';

  bool get isNewService => requestType == 'new_service';
  bool get isPriceChange => requestType == 'price_change';
  bool get isDeleteService => requestType == 'delete_service';
  bool get isEditService => requestType == 'edit_service';

  String get statusLabel => switch (status) {
        'needs_catalog' => 'Needs Catalog',
        'completed' => 'Completed',
        'rejected' => 'Rejected',
        'pending_deletion' => 'Pending Deletion',
        'deleted' => 'Deleted',
        _ => 'Pending',
      };

  String get requestTypeLabel => switch (requestType) {
        'price_change' => 'Price Change',
        'delete_service' => 'Deletion',
        'edit_service' => 'Edit Proposal',
        // new_service rows that are awaiting deletion approval
        _ => isPendingDeletion ? 'Deletion Request' : 'New Service',
      };

  String get formattedDate =>
      DateFormat('dd MMM yyyy, hh:mm a').format(createdAt.toLocal());

  String get formattedPrice =>
      price != null ? '₹${price!.toStringAsFixed(0)}' : '—';

  String get formattedActivePrice =>
      activePrice != null ? '₹${activePrice!.toStringAsFixed(0)}' : '—';

  String get formattedNewPrice =>
      newPrice != null ? '₹${newPrice!.toStringAsFixed(0)}' : '—';

  factory VendorServiceRequest.fromMap(Map<String, dynamic> m) {
    final vendor = m['vendors'] as Map<String, dynamic>? ?? {};
    final tierMap = vendor['vendor_tiers'] as Map<String, dynamic>?;
    return VendorServiceRequest(
      id: m['id'] as String,
      vendorId: m['vendor_id'] as String,
      vendorName: vendor['business_name'] as String? ?? '—',
      vendorTier: tierMap?['name'] as String?,
      serviceName: m['service_name'] as String,
      description: m['description'] as String?,
      price: (m['price'] as num?)?.toDouble(),
      activePrice: (m['active_price'] as num?)?.toDouble(),
      newPrice: (m['new_price'] as num?)?.toDouble(),
      imageUrl: m['image_url'] as String?,
      status: m['status'] as String? ?? 'pending',
      rejectionReason: m['rejection_reason'] as String?,
      requestType: m['request_type'] as String? ?? 'new_service',
      parentRequestId: m['parent_request_id'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
      isActive: m['is_active'] as bool? ?? false,
      warrantyEnabled: m['warranty_enabled'] as bool? ?? false,
      warrantyDays: m['warranty_days'] as int?,
      warrantyCovers: m['warranty_covers'] as String?,
      warrantyExclusions: m['warranty_exclusions'] as String?,
      includedItems: List<String>.from((m['included_items'] as List?) ?? []),
      excludedItems: List<String>.from((m['excluded_items'] as List?) ?? []),
      beforeAfterPairs: ((m['before_after_pairs'] as List?) ?? [])
          .map((e) => Map<String, String>.from(
              (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
          .toList(),
    );
  }
}
