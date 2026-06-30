class Service {
  final String id;
  final String categoryId;
  final String categoryName;
  final String subCategoryId;
  final String subCategoryName;
  final String name;
  final String slug;
  final double basePrice;
  final int estimatedDuration;
  final String? imageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Service({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.subCategoryId,
    required this.subCategoryName,
    required this.name,
    required this.slug,
    required this.basePrice,
    required this.estimatedDuration,
    this.imageUrl,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory Service.fromMap(Map<String, dynamic> map) {
    final categoryJoin = map['categories'] as Map<String, dynamic>?;
    final subCategoryJoin = map['sub_categories'] as Map<String, dynamic>?;
    return Service(
      id: map['id'] as String,
      categoryId: map['category_id'] as String? ?? '',
      categoryName: categoryJoin?['name'] as String? ?? '',
      subCategoryId: map['sub_category_id'] as String? ?? '',
      subCategoryName: subCategoryJoin?['name'] as String? ?? '',
      name: map['name'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      basePrice: (map['base_price'] as num?)?.toDouble() ?? 0.0,
      estimatedDuration: map['estimated_duration'] as int? ?? 0,
      imageUrl: map['image_url'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Service copyWith({
    String? categoryId,
    String? categoryName,
    String? subCategoryId,
    String? subCategoryName,
    String? name,
    String? slug,
    double? basePrice,
    int? estimatedDuration,
    String? imageUrl,
    bool? isActive,
  }) {
    return Service(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      subCategoryName: subCategoryName ?? this.subCategoryName,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      basePrice: basePrice ?? this.basePrice,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
