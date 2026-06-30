class CategoryModel {
  final String id;
  final String name;
  final String? iconKey;
  final String? iconUrl;
  final String? imageUrl;
  final int serviceCount;
  final String? description;
  final bool isActive;

  const CategoryModel({
    required this.id,
    required this.name,
    this.iconKey,
    this.iconUrl,
    this.imageUrl,
    this.serviceCount = 0,
    this.description,
    this.isActive = true,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      iconKey: json['icon_key'] as String?,
      iconUrl: json['icon'] as String?,
      imageUrl: json['image_url'] as String?,
      serviceCount: (json['service_count'] as int?) ?? 0,
      description: json['description'] as String?,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
