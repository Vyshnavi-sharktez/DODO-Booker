class ServingArea {
  const ServingArea({
    required this.id,
    required this.name,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.isActive,
  });

  final String id;
  final String name;
  final String city;
  final double latitude;
  final double longitude;
  final double radiusKm;
  final bool isActive;

  factory ServingArea.fromMap(Map<String, dynamic> m) => ServingArea(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        city: m['city'] as String? ?? '',
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        radiusKm: (m['radius_km'] as num?)?.toDouble() ?? 5.0,
        isActive: m['is_active'] as bool? ?? true,
      );
}
