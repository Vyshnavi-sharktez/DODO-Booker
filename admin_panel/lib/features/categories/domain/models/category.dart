class Category {
  final String id;
  final String name;
  final String slug;
  final String? imageUrl;
  final int sortOrder;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Category({
    required this.id,
    required this.name,
    required this.slug,
    this.imageUrl,
    required this.sortOrder,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
  });

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      imageUrl: map['image_url'] as String?,
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

  Category copyWith({
    String? name,
    String? slug,
    String? imageUrl,
    int? sortOrder,
    bool? isActive,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      imageUrl: imageUrl ?? this.imageUrl,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
