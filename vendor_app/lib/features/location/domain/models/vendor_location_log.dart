class VendorLocationLog {
  const VendorLocationLog({
    required this.id,
    required this.bookingId,
    required this.vendorId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.recordedAt,
  });

  final String id;
  final String bookingId;
  final String vendorId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime recordedAt;

  factory VendorLocationLog.fromMap(Map<String, dynamic> map) {
    return VendorLocationLog(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      vendorId: map['vendor_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(map['recorded_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'booking_id': bookingId,
      'vendor_id': vendorId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}
