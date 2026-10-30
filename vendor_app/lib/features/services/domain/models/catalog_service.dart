import 'package:flutter/foundation.dart';

/// Mirrors the columns returned by catalog_nodes_view.
/// Populated from the same .select() query that the Admin panel uses —
/// no separate field list, no artificial nesting.
@immutable
class CatalogService {
  const CatalogService({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.imageUrl,
    this.mobileImageUrl,
    this.iconKey,
    this.parentName,
    this.sortOrder = 0,
    this.isActive = true,
    this.isBookable = false,
    this.basePrice = 0.0,
    this.estimatedDuration,
    this.discountType = 'percentage',
    this.discountValue = 0,
    this.rating,
    this.reviewCount = 0,
    this.childrenCount = 0,
    this.includedItems = const [],
    this.excludedItems = const [],
    this.beforeAfterPairs = const [],
    this.warrantyEnabled = false,
    this.warrantyDays,
    this.warrantyCovers,
    this.warrantyExclusions,
  });

  final String id;
  final String name;
  final String? slug;
  final String? description;
  final String? imageUrl;
  final String? mobileImageUrl;
  final String? iconKey;

  /// parent_name from catalog_nodes_view — the canonical category label.
  final String? parentName;

  final int sortOrder;
  final bool isActive;
  final bool isBookable;
  final double basePrice;
  final int? estimatedDuration;
  final String discountType;
  final double discountValue;
  final double? rating;
  final int reviewCount;
  final int childrenCount;

  // ── Detail fields — populated from catalog_nodes_view full .select() ─────
  final List<String> includedItems;
  final List<String> excludedItems;
  final List<Map<String, String>> beforeAfterPairs;
  final bool warrantyEnabled;
  final int? warrantyDays;
  final String? warrantyCovers;
  final String? warrantyExclusions;

  // ── Backward-compatible accessors used by CatalogServiceTile ─────────────
  String? get categoryName => parentName;
  // catalog_nodes_view exposes a single parent_name; there is no separate
  // sub-category column, so this always returns null.
  String? get subCategoryName => null;

  double get discountAmount => discountType == 'percentage'
      ? basePrice * discountValue / 100
      : discountValue;

  double get finalPrice => (basePrice - discountAmount).clamp(0.0, double.infinity);

  bool get hasDiscount => discountValue > 0;

  factory CatalogService.fromMap(Map<String, dynamic> map) {
    return CatalogService(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      slug: map['slug'] as String?,
      description: map['description'] as String?,
      imageUrl: map['image_url'] as String?,
      mobileImageUrl: map['mobile_image_url'] as String?,
      iconKey: map['icon_key'] as String?,
      parentName: map['parent_name'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isActive: (map['is_active'] as bool?) ?? true,
      isBookable: (map['is_bookable'] as bool?) ?? false,
      basePrice: ((map['base_price'] as num?)?.toDouble()) ?? 0.0,
      estimatedDuration: map['estimated_duration'] as int?,
      discountType: (map['discount_type'] as String?) ?? 'percentage',
      discountValue: ((map['discount_value'] as num?)?.toDouble()) ?? 0,
      rating: (map['rating'] as num?)?.toDouble(),
      reviewCount: (map['review_count'] as int?) ?? 0,
      childrenCount: (map['children_count'] as int?) ?? 0,
      includedItems: (map['included_items'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [],
      excludedItems: (map['excluded_items'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [],
      beforeAfterPairs: (map['before_after_pairs'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(
                  (e as Map).map((k, v) => MapEntry(k.toString(), v.toString()))))
              .toList() ??
          [],
      warrantyEnabled: (map['warranty_enabled'] as bool?) ?? false,
      warrantyDays: map['warranty_days'] as int?,
      warrantyCovers: map['warranty_covers'] as String?,
      warrantyExclusions: map['warranty_exclusions'] as String?,
    );
  }
}
