class CatalogService {
  const CatalogService({
    required this.id,
    required this.name,
    this.categoryName,
    this.subCategoryName,
    this.basePrice = 0.0,
    this.estimatedDuration,
  });

  final String id;
  final String name;
  final String? categoryName;
  final String? subCategoryName;
  final double basePrice;
  final int? estimatedDuration;

  factory CatalogService.fromMap(Map<String, dynamic> map) {
    final category = map['categories'] as Map<String, dynamic>?;
    final subCategory = map['sub_categories'] as Map<String, dynamic>?;

    return CatalogService(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      categoryName: category?['name'] as String?,
      subCategoryName: subCategory?['name'] as String?,
      basePrice: (map['base_price'] as num?)?.toDouble() ?? 0.0,
      estimatedDuration: map['estimated_duration'] as int?,
    );
  }
}
