class CmsPage {
  final String id;
  final String pageSlug;
  final String pageTitle;
  final String? pageContent;
  final bool isPublished;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CmsPage({
    required this.id,
    required this.pageSlug,
    required this.pageTitle,
    this.pageContent,
    required this.isPublished,
    this.createdAt,
    this.updatedAt,
  });

  factory CmsPage.fromMap(Map<String, dynamic> map) {
    return CmsPage(
      id: map['id'] as String,
      pageSlug: map['page_slug'] as String? ?? '',
      pageTitle: map['page_title'] as String? ?? '',
      pageContent: map['page_content'] as String?,
      isPublished: map['is_published'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  CmsPage copyWith({
    String? pageSlug,
    String? pageTitle,
    String? pageContent,
    bool? isPublished,
  }) {
    return CmsPage(
      id: id,
      pageSlug: pageSlug ?? this.pageSlug,
      pageTitle: pageTitle ?? this.pageTitle,
      pageContent: pageContent ?? this.pageContent,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
