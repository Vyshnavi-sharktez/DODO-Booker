class SubcategoryModel {
  final String id;
  final String name;
  final String categoryId;
  final String? iconUrl;
  final String? imageUrl;
  final String? description;
  final int serviceCount;
  final bool isActive;

  const SubcategoryModel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.iconUrl,
    this.imageUrl,
    this.description,
    this.serviceCount = 0,
    this.isActive = true,
  });

  factory SubcategoryModel.fromJson(Map<String, dynamic> json) {
    return SubcategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['category_id'] as String,
      iconUrl: json['icon_url'] as String?,
      imageUrl: json['image_url'] as String?,
      description: json['description'] as String?,
      serviceCount: (json['service_count'] as int?) ?? 0,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
