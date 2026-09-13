class VendorServiceRequestModel {
  const VendorServiceRequestModel({
    required this.id,
    required this.serviceName,
    required this.status,
    required this.requestType,
    this.description,
    this.price,
    this.activePrice,
    this.newPrice,
    this.imageUrl,
    this.rejectionReason,
    this.parentRequestId,
    this.createdAt,
    this.isActive = false,
  });

  final String id;
  final String serviceName;
  final String status;
  final String requestType; // 'new_service' | 'price_change' | 'delete_service'
  final String? description;
  final double? price;
  final double? activePrice;
  final double? newPrice;
  final String? imageUrl;
  final String? rejectionReason;
  final String? parentRequestId;
  final DateTime? createdAt;
  final bool isActive;

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

  /// Shown in Custom Services: approved service, including while deletion is pending.
  bool get isActiveCustomService => isNewService && (isCompleted || isPendingDeletion);

  /// The current live price shown to customers.
  double? get currentPrice => activePrice ?? price;

  String get formattedPrice =>
      price != null ? '₹${price!.toStringAsFixed(0)}' : '—';

  String get formattedActivePrice =>
      activePrice != null ? '₹${activePrice!.toStringAsFixed(0)}' : formattedPrice;

  String get formattedNewPrice =>
      newPrice != null ? '₹${newPrice!.toStringAsFixed(0)}' : '—';

  String get formattedDate {
    if (createdAt == null) return '—';
    final d = createdAt!.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String get requestTypeLabel => switch (requestType) {
        'price_change' => 'Price Change',
        'delete_service' => 'Deletion',
        'edit_service' => 'Edit Proposal',
        _ => 'New Service',
      };

  factory VendorServiceRequestModel.fromMap(Map<String, dynamic> m) {
    return VendorServiceRequestModel(
      id: m['id'] as String,
      serviceName: m['service_name'] as String? ?? '',
      status: m['status'] as String? ?? 'pending',
      requestType: m['request_type'] as String? ?? 'new_service',
      description: m['description'] as String?,
      price: (m['price'] as num?)?.toDouble(),
      activePrice: (m['active_price'] as num?)?.toDouble(),
      newPrice: (m['new_price'] as num?)?.toDouble(),
      imageUrl: m['image_url'] as String?,
      rejectionReason: m['rejection_reason'] as String?,
      parentRequestId: m['parent_request_id'] as String?,
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'] as String)
          : null,
      isActive: m['is_active'] as bool? ?? false,
    );
  }
}
