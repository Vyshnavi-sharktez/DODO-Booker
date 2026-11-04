class VendorRootCategory {
  const VendorRootCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    required this.serviceCount,
    required this.vendorCount,
    this.iconUrl,
    this.vendorId,
  });

  final String id;
  final String name;
  final String? iconUrl;
  final int sortOrder;
  final String? vendorId;
  final DateTime createdAt;
  final int serviceCount;
  final int vendorCount;

  bool get isAdminCreated => vendorId == null;

  factory VendorRootCategory.fromMap(Map<String, dynamic> m) {
    return VendorRootCategory(
      id: m['id'] as String,
      name: m['name'] as String,
      iconUrl: m['icon_url'] as String?,
      sortOrder: (m['sort_order'] as int?) ?? 0,
      vendorId: m['vendor_id'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
      serviceCount: (m['service_count'] as int?) ?? 0,
      vendorCount: (m['vendor_count'] as int?) ?? 0,
    );
  }

  VendorRootCategory copyWith({
    String? name,
    String? iconUrl,
    int? sortOrder,
    bool clearIconUrl = false,
  }) {
    return VendorRootCategory(
      id: id,
      name: name ?? this.name,
      iconUrl: clearIconUrl ? null : (iconUrl ?? this.iconUrl),
      sortOrder: sortOrder ?? this.sortOrder,
      vendorId: vendorId,
      createdAt: createdAt,
      serviceCount: serviceCount,
      vendorCount: vendorCount,
    );
  }
}
