class VendorCategoryModel {
  const VendorCategoryModel({
    required this.id,
    required this.name,
    this.iconUrl,
    this.serviceCount = 0,
  });

  final String id;
  final String name;
  final String? iconUrl;
  final int serviceCount;

  factory VendorCategoryModel.fromMap(Map<String, dynamic> m) {
    return VendorCategoryModel(
      id: m['id'] as String,
      name: m['name'] as String,
      iconUrl: m['icon_url'] as String?,
      serviceCount: (m['service_count'] as num?)?.toInt() ?? 0,
    );
  }
}
