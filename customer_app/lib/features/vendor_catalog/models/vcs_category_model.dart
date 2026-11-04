class VcsCategoryModel {
  const VcsCategoryModel({
    required this.id,
    required this.name,
    this.slug,
    this.iconKey,
    this.imageUrl,
    this.sortOrder = 0,
    this.vendorCount = 0,
  });

  final String id;
  final String name;
  final String? slug;
  final String? iconKey;
  final String? imageUrl;
  final int sortOrder;
  final int vendorCount;

  factory VcsCategoryModel.fromMap(Map<String, dynamic> m) {
    return VcsCategoryModel(
      id: m['id'] as String,
      name: m['name'] as String,
      slug: m['slug'] as String?,
      iconKey: m['icon_key'] as String?,
      imageUrl: m['image_url'] as String?,
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      vendorCount: (m['vendor_count'] as num?)?.toInt() ?? 0,
    );
  }
}
