import 'catalog_node_seo.dart';

/// SEO configuration for a specific area × catalog node combination.
///
/// Stored in [location_node_seo]; one optional row per (area, node) pair.
/// Rows only exist for combinations the admin has explicitly configured.
///
/// The health status mirrors [CatalogNodeSeo.healthStatus] so the Location
/// Pages tab can reuse the same [SeoHealthStatus] enum and [_HealthDot] widget.
class LocationNodeSeo {
  final String id;
  final String areaId;
  final String nodeId;

  final String? seoTitle;
  final String? seoDescription;

  final String? ogTitle;
  final String? ogDescription;
  final String? ogImageUrl;

  /// Area-specific editorial body text — the primary content differentiator
  /// from the generic service page.
  final String? seoContent;

  final bool noindex;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LocationNodeSeo({
    required this.id,
    required this.areaId,
    required this.nodeId,
    this.seoTitle,
    this.seoDescription,
    this.ogTitle,
    this.ogDescription,
    this.ogImageUrl,
    this.seoContent,
    required this.noindex,
    this.createdAt,
    this.updatedAt,
  });

  factory LocationNodeSeo.fromMap(Map<String, dynamic> map) {
    return LocationNodeSeo(
      id: map['id'] as String,
      areaId: map['area_id'] as String,
      nodeId: map['node_id'] as String,
      seoTitle: map['seo_title'] as String?,
      seoDescription: map['seo_description'] as String?,
      ogTitle: map['og_title'] as String?,
      ogDescription: map['og_description'] as String?,
      ogImageUrl: map['og_image_url'] as String?,
      seoContent: map['seo_content'] as String?,
      noindex: (map['noindex'] as bool?) ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  SeoHealthStatus get healthStatus {
    if (noindex) return SeoHealthStatus.noindex;

    final hasTitle = seoTitle != null && seoTitle!.trim().isNotEmpty;
    final hasDesc =
        seoDescription != null && seoDescription!.trim().isNotEmpty;

    if (!hasTitle && !hasDesc) return SeoHealthStatus.notConfigured;
    if (!hasTitle || !hasDesc) return SeoHealthStatus.needsAttention;

    final titleTooLong = seoTitle!.trim().length > 70;
    final descTooLong = seoDescription!.trim().length > 180;
    if (titleTooLong || descTooLong) return SeoHealthStatus.needsAttention;

    return SeoHealthStatus.basicConfigured;
  }
}
