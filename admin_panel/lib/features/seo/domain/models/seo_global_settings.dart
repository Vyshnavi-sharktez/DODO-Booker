/// Global brand-level SEO defaults.
///
/// Stored in [seo_global_settings] as a singleton row (id = 'global').
/// All fields are nullable — admin fills them in progressively.
/// No production values are hardcoded here.
///
/// Ownership:
///   • Per-node SEO  → [CatalogNodeSeo]
///   • CMS page SEO  → existing SeoSetting / seo_settings table
class SeoGlobalSettings {
  /// Always 'global' — enforced by a DB CHECK constraint.
  final String id;

  final String? brandName;
  final String? brandTagline;

  /// Production domain (e.g. https://example.com).
  /// Null until hosting is finalised; the SERP preview shows a placeholder.
  final String? productionDomain;

  /// Fallback OG/social image for pages that have no node-level override.
  final String? defaultOgImageUrl;

  /// Title template for generated SEO pages.
  /// May contain {page_title} as a placeholder, e.g. "{page_title} | DODO Booker".
  final String? titleTemplate;

  final String? homepageSeoTitle;
  final String? homepageSeoDescription;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Set by the SEO generator ONLY after all pages are generated and
  /// validation passes. Never null-compared against updatedAt for staleness.
  final DateTime? lastGenerationAt;

  const SeoGlobalSettings({
    this.id = 'global',
    this.brandName,
    this.brandTagline,
    this.productionDomain,
    this.defaultOgImageUrl,
    this.titleTemplate,
    this.homepageSeoTitle,
    this.homepageSeoDescription,
    this.createdAt,
    this.updatedAt,
    this.lastGenerationAt,
  });

  factory SeoGlobalSettings.fromMap(Map<String, dynamic> map) {
    return SeoGlobalSettings(
      id: map['id'] as String? ?? 'global',
      brandName: map['brand_name'] as String?,
      brandTagline: map['brand_tagline'] as String?,
      productionDomain: map['production_domain'] as String?,
      defaultOgImageUrl: map['default_og_image_url'] as String?,
      titleTemplate: map['title_template'] as String?,
      homepageSeoTitle: map['homepage_seo_title'] as String?,
      homepageSeoDescription: map['homepage_seo_description'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
      lastGenerationAt: map['last_generation_at'] != null
          ? DateTime.tryParse(map['last_generation_at'] as String)
          : null,
    );
  }
}
