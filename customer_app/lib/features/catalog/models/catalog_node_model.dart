import '../../../models/service_model.dart';

class CatalogNodeModel {
  final String id;
  final String? parentId;
  final String? parentName;
  final String name;
  final String slug;
  final String? description;
  final String? imageUrl;
  final String? iconKey;
  final int sortOrder;
  final bool isActive;
  final bool isFeatured;

  /// Admin-controlled flag. Never derived from children. The customer should
  /// be able to book this node if and only if this is true.
  final bool isBookable;

  final double? basePrice;
  final int? estimatedDuration;
  final double rating;
  final int reviewCount;

  /// Count of active direct children. Non-zero means further navigation is
  /// possible; zero means this is a leaf regardless of isBookable.
  final int childrenCount;

  /// The UUID of the original row in the legacy `services` table.
  /// Non-null for nodes migrated from services (legacy_type = 'service').
  /// Null for brand-new catalog nodes created directly via the admin panel.
  ///
  /// Used as `service_id` when inserting into `booking_items`, which still
  /// carries a FK to `services(id)`. New catalog nodes (legacyId == null)
  /// cannot populate `booking_items` until the schema is migrated.
  final String? legacyId;

  const CatalogNodeModel({
    required this.id,
    this.parentId,
    this.parentName,
    required this.name,
    required this.slug,
    this.description,
    this.imageUrl,
    this.iconKey,
    required this.sortOrder,
    required this.isActive,
    required this.isFeatured,
    required this.isBookable,
    this.basePrice,
    this.estimatedDuration,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.childrenCount = 0,
    this.legacyId,
  });

  bool get hasChildren => childrenCount > 0;
  bool get isRoot => parentId == null;

  /// True only when BOTH conditions are met:
  ///   1. is_bookable == true  (admin has enabled booking)
  ///   2. children_count == 0  (no child nodes exist)
  ///
  /// A node with children is always a navigation node, never a bookable leaf,
  /// even when is_bookable is set to true in the database.
  bool get isLeafBookable => isBookable && !hasChildren;

  factory CatalogNodeModel.fromServiceModel(ServiceModel s) => CatalogNodeModel(
        id: s.id,
        legacyId: s.id,
        name: s.name,
        slug: s.id,
        description: s.description,
        imageUrl: s.imageUrl,
        sortOrder: 0,
        isActive: s.isActive,
        isFeatured: s.isFeatured,
        isBookable: true,
        basePrice: s.startingPrice,
        estimatedDuration: s.durationMinutes,
        parentName: s.subcategoryName ?? s.categoryName,
        rating: s.rating,
        reviewCount: s.reviewCount,
        childrenCount: 0,
      );

  factory CatalogNodeModel.fromMap(Map<String, dynamic> map) {
    return CatalogNodeModel(
      id: map['id'] as String,
      legacyId: map['legacy_id'] as String?,
      parentId: map['parent_id'] as String?,
      parentName: map['parent_name'] as String?,
      name: map['name'] as String,
      slug: map['slug'] as String,
      description: map['description'] as String?,
      imageUrl: map['image_url'] as String?,
      iconKey: map['icon_key'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isActive: (map['is_active'] as bool?) ?? true,
      isFeatured: (map['is_featured'] as bool?) ?? false,
      isBookable: (map['is_bookable'] as bool?) ?? false,
      basePrice: (map['base_price'] as num?)?.toDouble(),
      estimatedDuration: map['estimated_duration'] as int?,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (map['review_count'] as int?) ?? 0,
      childrenCount: (map['children_count'] as int?) ?? 0,
    );
  }
}
