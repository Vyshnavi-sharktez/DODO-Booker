class LandingPageSection {
  final String id;
  final String sectionType;
  final String sectionName;
  final int displayOrder;
  final bool isEnabled;
  final bool isPublished;
  final Map<String, dynamic> config;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const LandingPageSection({
    required this.id,
    required this.sectionType,
    required this.sectionName,
    required this.displayOrder,
    required this.isEnabled,
    required this.isPublished,
    required this.config,
    this.createdAt,
    this.updatedAt,
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
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'section_type': sectionType,
      'section_name': sectionName,
      'display_order': displayOrder,
      'is_enabled': isEnabled,
      'is_published': isPublished,
      'config': config,
    };
  }

  LandingPageSection copyWith({
    String? sectionName,
    int? displayOrder,
    bool? isEnabled,
    bool? isPublished,
    Map<String, dynamic>? config,
  }) {
    return LandingPageSection(
      id: id,
      sectionType: sectionType,
      sectionName: sectionName ?? this.sectionName,
      displayOrder: displayOrder ?? this.displayOrder,
      isEnabled: isEnabled ?? this.isEnabled,
      isPublished: isPublished ?? this.isPublished,
      config: config ?? this.config,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  T? configValue<T>(String key) => config[key] as T?;
}
