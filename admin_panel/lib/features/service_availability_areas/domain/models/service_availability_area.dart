class ServiceAvailabilityArea {
  const ServiceAvailabilityArea({
    required this.id,
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.isActive,
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
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'] as String)
            : null,
        updatedAt: m['updated_at'] != null
            ? DateTime.tryParse(m['updated_at'] as String)
            : null,
      );

  Map<String, dynamic> toInsertMap() => {
        'name': name,
        'city': city,
        'latitude': latitude,
        'longitude': longitude,
        'radius_km': radiusKm,
        'is_active': isActive,
      };
}
