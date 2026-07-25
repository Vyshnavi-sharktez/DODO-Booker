/// Aggregate SEO coverage metrics for the overview card.
///
/// Fetched in one parallel batch by [SeoRepository.fetchSeoCoverageStats].
/// [latestSeoUpdatedAt] covers catalog_node_seo and location_node_seo;
/// compare it alongside [SeoGlobalSettings.updatedAt] for a complete
/// staleness picture.
class SeoCoverageStats {
  /// Catalog nodes with seo_title configured and noindex = false.
  final int configuredCatalogCount;

  /// All active nodes in catalog_nodes_view (total eligible for SEO).
  final int totalActiveCatalogNodes;

  /// location_node_seo entries with seo_title configured and noindex = false.
  /// Zero when the location_node_seo table does not yet exist.
  final int configuredLocationCount;

  /// Active service availability areas (useful for location coverage context).
  final int totalActiveAreas;

  /// Latest updated_at across catalog_node_seo + location_node_seo.
  /// Null if no SEO rows exist yet.
  final DateTime? latestSeoUpdatedAt;

  const SeoCoverageStats({
    required this.configuredCatalogCount,
    required this.totalActiveCatalogNodes,
    required this.configuredLocationCount,
    required this.totalActiveAreas,
    this.latestSeoUpdatedAt,
  });

  int get unconfiguredCatalogCount =>
      (totalActiveCatalogNodes - configuredCatalogCount).clamp(0, totalActiveCatalogNodes);
}
