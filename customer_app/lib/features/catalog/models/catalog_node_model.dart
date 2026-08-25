import '../../../models/service_model.dart';

class CatalogNodeModel {
  final String id;

  /// All parent category IDs, ordered by sort_order.
  /// Empty list means this is a top-level item.
  final List<String> parentIds;

  /// Name of the canonical (first) parent — for display only.
  final String? parentName;

  final String name;
  final String slug;
  final String? description;
  final String? imageUrl;
  final String? iconKey;
  final int sortOrder;
  final bool isActive;
  final bool isFeatured;

  /// Admin-controlled flag. Never derived from children.
  final bool isBookable;

  final double? basePrice;
  final int? estimatedDuration;
  final double? minimumOrderAmount;
  final double rating;
  final int reviewCount;

  /// Count of active direct children.
  final int childrenCount;

  // ── Availability (from catalog_nodes.availability_status) ───────────────────
  /// Node-scoped availability: 'active' | 'unavailable' | 'hidden'.
  /// For path-aware availability use the nodeAvailabilityProvider instead.
  final String availabilityStatus;
  final String? unavailabilityMessage;

  /// Relationship-scoped availability for the specific parent→child edge used
  /// to fetch this node. Populated only when fetched via get_catalog_node_children;
  /// falls back to [availabilityStatus] for direct/root fetches.
  /// Use this for inline child-list badges so shared nodes appear correctly
  /// under each parent independently.
  final String relAvailabilityStatus;

  // ── Loyalty earn config (mirrors catalog_nodes.loyalty_earn_* columns) ──────
  final bool loyaltyEarnEnabled;
  /// 'global' | 'fixed' | 'percentage'
  final String loyaltyEarnRule;
  final int? loyaltyFixedPoints;
  final int? loyaltyEarnPer100;

  // ── Per-node content fields ───────────────────────────────────────────────
  final List<String> includedItems;
  final List<String> excludedItems;
  /// Each entry is {'before_url': '...', 'after_url': '...'}.
  final List<Map<String, String>> beforeAfterPairs;

  /// Flexible content blocks shown on the service page.
  /// Each entry: {'id', 'type': 'text'|'image'|'image_text', 'text'?, 'image_url'?}.
  final List<Map<String, dynamic>> contentBlocks;

  const CatalogNodeModel({
    required this.id,
    this.parentIds = const [],
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
    this.minimumOrderAmount,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.childrenCount = 0,
    this.availabilityStatus = 'active',
    this.unavailabilityMessage,
    this.relAvailabilityStatus = 'active',
    this.loyaltyEarnEnabled = true,
    this.loyaltyEarnRule = 'global',
    this.loyaltyFixedPoints,
    this.loyaltyEarnPer100,
    this.includedItems = const [],
    this.excludedItems = const [],
    this.beforeAfterPairs = const [],
    this.contentBlocks = const [],
  });

  bool get hasChildren => childrenCount > 0;

  /// True when this item has no parent categories.
  bool get isRoot => parentIds.isEmpty;

  /// True when this item is listed under more than one category.
  bool get isShared => parentIds.length > 1;

  /// Canonical (first) parent ID — null when top-level.
  String? get parentId => parentIds.isEmpty ? null : parentIds.first;

  /// Customers can book this item only when it is bookable AND has no children
  /// (a node with children is a navigation category, not a bookable service).
  bool get isLeafBookable => isBookable && !hasChildren;

  CatalogNodeModel copyWith({String? parentName}) {
    return CatalogNodeModel(
      id: id,
      parentIds: parentIds,
      parentName: parentName ?? this.parentName,
      name: name,
      slug: slug,
      description: description,
      imageUrl: imageUrl,
      iconKey: iconKey,
      sortOrder: sortOrder,
      isActive: isActive,
      isFeatured: isFeatured,
      isBookable: isBookable,
      basePrice: basePrice,
      estimatedDuration: estimatedDuration,
      minimumOrderAmount: minimumOrderAmount,
      rating: rating,
      reviewCount: reviewCount,
      childrenCount: childrenCount,
      availabilityStatus: availabilityStatus,
      unavailabilityMessage: unavailabilityMessage,
      relAvailabilityStatus: relAvailabilityStatus,
      loyaltyEarnEnabled: loyaltyEarnEnabled,
      loyaltyEarnRule: loyaltyEarnRule,
      loyaltyFixedPoints: loyaltyFixedPoints,
      loyaltyEarnPer100: loyaltyEarnPer100,
      includedItems: includedItems,
      excludedItems: excludedItems,
      beforeAfterPairs: beforeAfterPairs,
      contentBlocks: contentBlocks,
    );
  }

  factory CatalogNodeModel.fromServiceModel(ServiceModel s) =>
      CatalogNodeModel(
        id: s.id,
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
      parentIds: (map['parent_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
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
      minimumOrderAmount: (map['minimum_order_amount'] as num?)?.toDouble(),
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      reviewCount: (map['review_count'] as int?) ?? 0,
      childrenCount: (map['children_count'] as int?) ?? 0,
      availabilityStatus: (map['availability_status'] as String?) ?? 'active',
      unavailabilityMessage: map['unavailability_message'] as String?,
      relAvailabilityStatus: (map['rel_availability_status'] as String?) ??
          (map['availability_status'] as String? ?? 'active'),
      loyaltyEarnEnabled: (map['loyalty_earn_enabled'] as bool?) ?? true,
      loyaltyEarnRule: (map['loyalty_earn_rule'] as String?) ?? 'global',
      loyaltyFixedPoints: map['loyalty_fixed_points'] as int?,
      loyaltyEarnPer100: map['loyalty_earn_per_100'] as int?,
      includedItems: (map['included_items'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      excludedItems: (map['excluded_items'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      beforeAfterPairs: (map['before_after_pairs'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(
                  (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
              .toList() ??
          [],
      contentBlocks: (map['content_blocks'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }
}
