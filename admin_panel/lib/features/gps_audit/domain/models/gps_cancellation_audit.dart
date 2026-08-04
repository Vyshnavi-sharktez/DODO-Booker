class GpsCancellationAudit {
  final String id;
  final String bookingId;
  final String vendorId;
  final String customerId;
  final String? nearestLocationLogId;
  final double minDistanceMeters;
  final double geofenceRadiusMeters;
  final double bookingLatitude;
  final double bookingLongitude;
  final double nearestLatitude;
  final double nearestLongitude;
  final double? nearestAccuracy;
  final DateTime nearestRecordedAt;
  final String? cancellationReason;
  final String auditStatus;
  final DateTime auditedAt;
  final DateTime createdAt;

  // Joined fields
  final String? bookingNumber;
  final String? customerName;
  final String? customerPhone;
  final String? vendorBusinessName;
  final String? vendorPhone;

  const GpsCancellationAudit({
    required this.id,
    required this.bookingId,
    required this.vendorId,
    required this.customerId,
    this.nearestLocationLogId,
    required this.minDistanceMeters,
    required this.geofenceRadiusMeters,
    required this.bookingLatitude,
    required this.bookingLongitude,
    required this.nearestLatitude,
    required this.nearestLongitude,
    this.nearestAccuracy,
    required this.nearestRecordedAt,
    this.cancellationReason,
    required this.auditStatus,
    required this.auditedAt,
    required this.createdAt,
    this.bookingNumber,
    this.customerName,
    this.customerPhone,
    this.vendorBusinessName,
    this.vendorPhone,
  });

  factory GpsCancellationAudit.fromMap(Map<String, dynamic> map) {
    final booking = map['bookings'] as Map<String, dynamic>?;
    final customer = map['customers'] as Map<String, dynamic>?;
    final vendor = map['vendors'] as Map<String, dynamic>?;

    return GpsCancellationAudit(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      vendorId: map['vendor_id'] as String,
      customerId: map['customer_id'] as String,
      nearestLocationLogId: map['nearest_location_log_id'] as String?,
      minDistanceMeters: (map['min_distance_meters'] as num).toDouble(),
      geofenceRadiusMeters: (map['geofence_radius_meters'] as num).toDouble(),
      bookingLatitude: (map['booking_latitude'] as num).toDouble(),
      bookingLongitude: (map['booking_longitude'] as num).toDouble(),
      nearestLatitude: (map['nearest_latitude'] as num).toDouble(),
      nearestLongitude: (map['nearest_longitude'] as num).toDouble(),
      nearestAccuracy: (map['nearest_accuracy'] as num?)?.toDouble(),
      nearestRecordedAt: DateTime.parse(map['nearest_recorded_at'] as String),
      cancellationReason: map['cancellation_reason'] as String?,
      auditStatus:
          map['audit_status'] as String? ?? 'potential_false_cancellation',
      auditedAt: DateTime.parse(map['audited_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      bookingNumber: booking?['booking_number'] as String?,
      customerName: customer?['full_name'] as String?,
      customerPhone: customer?['phone'] as String?,
      vendorBusinessName: vendor?['business_name'] as String?,
      vendorPhone: vendor?['phone'] as String?,
    );
  }

  GpsCancellationAudit copyWith({
    String? auditStatus,
  }) {
    return GpsCancellationAudit(
      id: id,
      bookingId: bookingId,
      vendorId: vendorId,
      customerId: customerId,
      nearestLocationLogId: nearestLocationLogId,
      minDistanceMeters: minDistanceMeters,
      geofenceRadiusMeters: geofenceRadiusMeters,
      bookingLatitude: bookingLatitude,
      bookingLongitude: bookingLongitude,
      nearestLatitude: nearestLatitude,
      nearestLongitude: nearestLongitude,
      nearestAccuracy: nearestAccuracy,
      nearestRecordedAt: nearestRecordedAt,
      cancellationReason: cancellationReason,
      auditStatus: auditStatus ?? this.auditStatus,
      auditedAt: auditedAt,
      createdAt: createdAt,
      bookingNumber: bookingNumber,
      customerName: customerName,
      customerPhone: customerPhone,
      vendorBusinessName: vendorBusinessName,
      vendorPhone: vendorPhone,
    );
  }
}
