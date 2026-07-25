class ServiceAvailabilityArea {
  const ServiceAvailabilityArea({
    required this.id,
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.isActive,
    this.slug,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String city;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final bool isActive;

  /// URL-safe slug for location SEO pages (e.g. "gachibowli").
  /// Added by Phase 4 migration. Null only on pre-migration rows
  /// that have not yet been updated — the migration backfills all existing rows
  /// so this should always be non-null in practice.
  final String? slug;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ServiceAvailabilityArea.fromMap(Map<String, dynamic> m) =>
      ServiceAvailabilityArea(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        city: m['city'] as String? ?? '',
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        radiusKm: (m['radius_km'] as num?)?.toDouble() ?? 5.0,
        isActive: m['is_active'] as bool? ?? true,
        slug: m['slug'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)
            : null,
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'] as String)
            : null,
      );

  // slug is intentionally omitted from toInsertMap: the DB trigger
  // fn_saa_auto_slug() derives it from name automatically on INSERT.
  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'radius_km': radiusKm,
        'is_active': isActive,
      };
}
