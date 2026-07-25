/// SEO configuration attached to a single catalog node.
///
/// Stored in [catalog_node_seo]; one optional row per node.
/// When no row exists, the node has no SEO configuration yet.
///
/// Ownership: this model owns per-node SEO only.
///   • Global defaults  → [SeoGlobalSettings]
///   • CMS page SEO     → existing [SeoSetting] / seo_settings table
class CatalogNodeSeo {
  final String id;
  final String nodeId;

  final String? seoTitle;
  final String? seoDescription;

  final String? ogTitle;
  final String? ogDescription;
  final String? ogImageUrl;

  final String? seoContent;

  /// Editorial guidance only — records the search intent this node targets.
  /// NOT stored as meta keywords. NOT auto-injected into any content.
  final String? primarySearchTopic;

  final bool noindex;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CatalogNodeSeo({
    required this.id,
    required this.nodeId,
    this.seoTitle,
    this.seoDescription,
    this.ogTitle,
    this.ogDescription,
    this.ogImageUrl,
    this.seoContent,
    this.primarySearchTopic,
    required this.noindex,
    this.createdAt,
    this.updatedAt,
  });

  factory CatalogNodeSeo.fromMap(Map<String, dynamic> map) {
    return CatalogNodeSeo(
      id: map['id'] as String,
      nodeId: map['node_id'] as String,
      seoTitle: map['seo_title'] as String?,
      seoDescription: map['seo_description'] as String?,
      ogTitle: map['og_title'] as String?,
      ogDescription: map['og_description'] as String?,
      ogImageUrl: map['og_image_url'] as String?,
      seoContent: map['seo_content'] as String?,
      primarySearchTopic: map['primary_search_topic'] as String?,
      noindex: (map['noindex'] as bool?) ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  /// Descriptive health state — NOT a guarantee of search-engine behaviour.
  SeoHealthStatus get healthStatus {
    if (noindex) return SeoHealthStatus.noindex;

    final hasTitle = seoTitle != null && seoTitle!.trim().isNotEmpty;
    final hasDesc =
        seoDescription != null && seoDescription!.trim().isNotEmpty;

    if (!hasTitle && !hasDesc) return SeoHealthStatus.notConfigured;
    if (!hasTitle || !hasDesc) return SeoHealthStatus.needsAttention;

    // Guidance thresholds only — not hard limits on actual display behaviour.
    final titleTooLong = seoTitle!.trim().length > 70;
    final descTooLong = seoDescription!.trim().length > 180;
    if (titleTooLong || descTooLong) return SeoHealthStatus.needsAttention;

    return SeoHealthStatus.basicConfigured;
  }
}

/// Descriptive SEO health states.
///
/// These labels describe the current configuration state only.
/// They do NOT claim that any state equals "SEO optimised".
enum SeoHealthStatus {
  /// No SEO row exists in the database for this node.
  notConfigured,

  /// Admin has set noindex — this node will be excluded from the sitemap
  /// and marked noindex in the generated page.
  noindex,

  /// Some metadata is present but incomplete or outside guidance thresholds.
  needsAttention,

  /// Both title and description are present and within guidance lengths.
  basicConfigured,
}

extension SeoHealthStatusLabel on SeoHealthStatus {
  String get label {
    switch (this) {
      case SeoHealthStatus.notConfigured:
        return 'Not configured';
      case SeoHealthStatus.noindex:
        return 'Noindex';
      case SeoHealthStatus.needsAttention:
        return 'Needs attention';
      case SeoHealthStatus.basicConfigured:
        return 'Basic metadata';
    }
  }
}
