class SeoSetting {
  final String id;
  final String pageSlug;
  final String? metaTitle;
  final String? metaDescription;
  final String? metaKeywords;
  final String? ogImageUrl;
  final String? canonicalUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SeoSetting({
    required this.id,
    required this.pageSlug,
    this.metaTitle,
    this.metaDescription,
    this.metaKeywords,
    this.ogImageUrl,
    this.canonicalUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory SeoSetting.fromMap(Map<String, dynamic> map) {
    return SeoSetting(
      id: map['id'] as String,
      pageSlug: map['page_slug'] as String? ?? '',
      metaTitle: map['meta_title'] as String?,
      metaDescription: map['meta_description'] as String?,
      metaKeywords: map['meta_keywords'] as String?,
      ogImageUrl: map['og_image_url'] as String?,
      canonicalUrl: map['canonical_url'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }
}
