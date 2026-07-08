class CatalogNode {
  final String id;
  final String? parentId;
  final String? parentName;
  final String? parentSlug;

  final String name;
  final String slug;
  final String? description;
  final String? imageUrl;
  final String? iconKey;
  final int sortOrder;

  /// Admin-controlled. Never derived from child presence.
  final bool isActive;
  final bool isBookable;

  /// Only meaningful when [isBookable] is true.
  final double? basePrice;
  final int? estimatedDuration;
  final double? minimumOrderAmount;
  final double? rating;
  final int reviewCount;

  /// Count of active children from the DB view.
  /// In the admin tree this is supplemented by the in-memory byParent map
  /// which includes inactive children too.
  final int childrenCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CatalogNode({
    required this.id,
    this.parentId,
    this.parentName,
    this.parentSlug,
    required this.name,
    required this.slug,
    this.description,
    this.imageUrl,
    this.iconKey,
    required this.sortOrder,
    required this.isActive,
    required this.isBookable,
    this.basePrice,
    this.estimatedDuration,
    this.minimumOrderAmount,
    this.rating,
    required this.reviewCount,
    required this.childrenCount,
    this.createdAt,
    this.updatedAt,
  });

  bool get isRoot => parentId == null;

  factory CatalogNode.fromMap(Map<String, dynamic> map) {
    return CatalogNode(
      id: map['id'] as String,
      parentId: map['parent_id'] as String?,
      parentName: map['parent_name'] as String?,
      parentSlug: map['parent_slug'] as String?,
      name: map['name'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      description: map['description'] as String?,
      imageUrl: map['image_url'] as String?,
      iconKey: map['icon_key'] as String?,
      sortOrder: map['sort_order'] as int? ?? 0,
      isActive: map['is_active'] as bool? ?? true,
      isBookable: map['is_bookable'] as bool? ?? false,
      basePrice: (map['base_price'] as num?)?.toDouble(),
      estimatedDuration: map['estimated_duration'] as int?,
      minimumOrderAmount: (map['minimum_order_amount'] as num?)?.toDouble(),
      rating: (map['rating'] as num?)?.toDouble(),
      reviewCount: map['review_count'] as int? ?? 0,
      childrenCount: map['children_count'] as int? ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  CatalogNode copyWith({
    String? parentId,
    String? parentName,
    String? name,
    String? slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    int? sortOrder,
    bool? isActive,
    bool? isBookable,
    double? basePrice,
    int? estimatedDuration,
    double? minimumOrderAmount,
    int? childrenCount,
  }) {
    return CatalogNode(
      id: id,
      parentId: parentId ?? this.parentId,
      parentName: parentName ?? this.parentName,
      parentSlug: parentSlug,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      iconKey: iconKey ?? this.iconKey,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      isBookable: isBookable ?? this.isBookable,
      basePrice: basePrice ?? this.basePrice,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      minimumOrderAmount: minimumOrderAmount ?? this.minimumOrderAmount,
      rating: rating,
      reviewCount: reviewCount,
      childrenCount: childrenCount ?? this.childrenCount,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
