class LandingPageSection {
  final String id;
  final String sectionType;
  final String sectionName;
  final int displayOrder;
  final bool isEnabled;
  final bool isPublished;
  final Map<String, dynamic> config;

  const LandingPageSection({
    required this.id,
    required this.sectionType,
    required this.sectionName,
    required this.displayOrder,
    required this.isEnabled,
    required this.isPublished,
    required this.config,
  });

  factory LandingPageSection.fromMap(Map<String, dynamic> map) {
    return LandingPageSection(
      id: map['id'] as String,
      sectionType: map['section_type'] as String,
      sectionName: map['section_name'] as String,
      displayOrder: map['display_order'] as int? ?? 0,
      isEnabled: map['is_enabled'] as bool? ?? true,
      isPublished: map['is_published'] as bool? ?? false,
      config: (map['config'] as Map<String, dynamic>?) ?? {},
    );
  }

  T? configValue<T>(String key) => config[key] as T?;
}
