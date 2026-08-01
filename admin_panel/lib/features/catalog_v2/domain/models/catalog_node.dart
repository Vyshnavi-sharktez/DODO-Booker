class CatalogNode {
  final String id;

  /// All parent IDs from the relationship table, ordered by sort_order.
  /// Empty list means this is a top-level (root) item.
  final List<String> parentIds;

  /// Name of the canonical (first) parent — for display only.
  final String? parentName;
  final String? parentSlug;

  final String name;
  final String slug;
  final String? description;
  final String? imageUrl;
  final String? iconKey;
  final int sortOrder;

  final bool isActive;
  final bool isBookable;

  /// Node-scoped availability status: 'active' | 'unavailable' | 'hidden'.
  /// For per-path control use setRelationshipAvailability instead.
  final String availabilityStatus;
  final String? unavailabilityMessage;

  final double? basePrice;
  final int? estimatedDuration;
  final double? minimumOrderAmount;
  final double? rating;
  final int reviewCount;

  // AMC (Annual Maintenance Contract) — service-level config
  final bool amcEnabled;
  final String? amcPlanName;
  final String? amcRecurrenceInterval;
  final int? amcContractDuration;
  final int? amcMaxVisits;
  final double? amcPricePerVisit;

  /// Count of active children from the DB view.
  final int childrenCount;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CatalogNode({
    required this.id,
    this.parentIds = const [],
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
    this.availabilityStatus = 'active',
    this.unavailabilityMessage,
    this.basePrice,
    this.estimatedDuration,
    this.minimumOrderAmount,
    this.rating,
    required this.reviewCount,
    this.amcEnabled = false,
    this.amcPlanName,
    this.amcRecurrenceInterval,
    this.amcContractDuration,
    this.amcMaxVisits,
    this.amcPricePerVisit,
    required this.childrenCount,
    this.createdAt,
    this.updatedAt,
  });

  /// True when this item has no parent categories.
  bool get isRoot => parentIds.isEmpty;

  /// True when this item appears under more than one parent category.
  bool get isShared => parentIds.length > 1;

  /// The canonical (first) parent ID — null when top-level.
  /// Kept for display convenience; do not use for relationship management.
  String? get primaryParentId => parentIds.isEmpty ? null : parentIds.first;

  /// Alias for [primaryParentId] — kept so legacy code still compiles.
  String? get parentId => primaryParentId;

  factory CatalogNode.fromMap(Map<String, dynamic> map) {
    return CatalogNode(
      id: map['id'] as String,
      parentIds: (map['parent_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
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
      availabilityStatus: map['availability_status'] as String? ?? 'active',
      unavailabilityMessage: map['unavailability_message'] as String?,
      basePrice: (map['base_price'] as num?)?.toDouble(),
      estimatedDuration: map['estimated_duration'] as int?,
      minimumOrderAmount: (map['minimum_order_amount'] as num?)?.toDouble(),
      rating: (map['rating'] as num?)?.toDouble(),
      reviewCount: map['review_count'] as int? ?? 0,
      amcEnabled: map['amc_enabled'] as bool? ?? false,
      amcPlanName: map['amc_plan_name'] as String?,
      amcRecurrenceInterval: map['amc_recurrence_interval'] as String?,
      amcContractDuration: map['amc_contract_duration'] as int?,
      amcMaxVisits: map['amc_max_visits'] as int?,
      amcPricePerVisit: (map['amc_price_per_visit'] as num?)?.toDouble(),
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
    List<String>? parentIds,
    String? parentName,
    String? name,
    String? slug,
    String? description,
    String? imageUrl,
    String? iconKey,
    int? sortOrder,
    bool? isActive,
    bool? isBookable,
    String? availabilityStatus,
    String? unavailabilityMessage,
    double? basePrice,
    int? estimatedDuration,
    double? minimumOrderAmount,
    int? childrenCount,
  }) {
    return CatalogNode(
      id: id,
      parentIds: parentIds ?? this.parentIds,
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
      availabilityStatus: availabilityStatus ?? this.availabilityStatus,
      unavailabilityMessage: unavailabilityMessage ?? this.unavailabilityMessage,
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
