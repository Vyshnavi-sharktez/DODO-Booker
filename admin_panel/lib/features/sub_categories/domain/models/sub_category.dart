class SubCategory {
  final String id;
  final String categoryId;
  final String categoryName;
  final String name;
  final String slug;
  final String? description;
  final int sortOrder;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SubCategory({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.slug,
    this.description,
    required this.sortOrder,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory SubCategory.fromMap(Map<String, dynamic> map) {
    final categoryJoin = map['categories'] as Map<String, dynamic>?;
    return SubCategory(
      id: map['id'] as String,
      categoryId: map['category_id'] as String? ?? '',
      categoryName: categoryJoin?['name'] as String? ?? '',
      name: map['name'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      description: map['description'] as String?,
      sortOrder: map['sort_order'] as int? ?? 0,
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  SubCategory copyWith({
    String? categoryId,
    String? categoryName,
    String? name,
    String? slug,
    String? description,
    int? sortOrder,
    bool? isActive,
  }) {
    return SubCategory(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
